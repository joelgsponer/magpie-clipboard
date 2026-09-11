import AVFoundation
import CoreAudio
import FluidAudio

enum DictationState: Equatable {
    case idle
    case requestingAccess
    case loadingModel
    case recording
    case transcribing
    case done(String)
    case error(String)
}

/// Thread-safe accumulator for audio buffers captured on the AVAudioEngine
/// tap callback, which does not run on the main thread. Owns its own locking
/// so it's safe to append from the tap and drain from the main actor.
private final class BufferAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    func drain() -> [AVAudioPCMBuffer] {
        lock.lock()
        let result = buffers
        buffers = []
        lock.unlock()
        return result
    }
}

/// Thread-safe rolling window of recent audio levels (RMS per tap buffer),
/// for driving a live waveform. Polled by the view via TimelineView rather
/// than published through Combine, so the audio-thread tap callback only
/// does a cheap lock + array shuffle instead of hopping to the main actor
/// on every buffer (dozens of times a second).
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var levels: [Float]

    init(capacity: Int) {
        levels = Array(repeating: 0, count: capacity)
    }

    func record(_ level: Float) {
        lock.lock()
        levels.removeFirst()
        levels.append(level)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        levels = levels.map { _ in 0 }
        lock.unlock()
    }

    func snapshot() -> [Float] {
        lock.lock()
        let result = levels
        lock.unlock()
        return result
    }
}

/// Captures the microphone and runs fully on-device speech-to-text via
/// FluidAudio's Parakeet TDT model (CoreML, Apple Neural Engine — audio
/// never leaves the Mac). Owns only the audio/recognition pipeline;
/// committing the result to the pasteboard/history is the caller's job
/// (see DictationWindow). Transcription is batch (whole recording at once,
/// after stop()) rather than live-streaming — Parakeet is fast enough
/// (~100x+ realtime) that this is effectively instant.
@MainActor
final class DictationManager: ObservableObject {
    static let shared = DictationManager()

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var recordingStartedAt: Date?

    // A fresh AVAudioEngine per recording session, not a long-lived shared
    // instance: reusing one engine across stop()/start() cycles reliably hits
    // "Failed to create tap due to format mismatch" on the second session —
    // a well-known AVAudioEngine quirk where the cached input format goes
    // stale after a prior stop(). Recreating the engine avoids it entirely.
    private var audioEngine: AVAudioEngine?
    private let bufferAccumulator = BufferAccumulator()
    let levelMeter = LevelMeter(capacity: 40)

    // Loaded once per app launch and reused across recording sessions —
    // AsrModels.downloadAndLoad fetches (first run only, cached to disk
    // after) and compiles a CoreML model, which is too slow to redo per
    // recording.
    private var asrManager: AsrManager?

    private var stopCompletion: ((String?) -> Void)?

    /// Invalidates stray async callbacks (permission results, model load,
    /// transcription) from a session the user has already cancelled or
    /// superseded.
    private var currentSessionID = UUID()

    private init() {}

    func start() {
        guard state == .idle else { return }
        state = .requestingAccess
        let sessionID = currentSessionID

        Microphone.requestIfNeeded { [weak self] granted in
            guard let self, sessionID == self.currentSessionID else { return }
            guard granted else {
                self.state = .error("Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.")
                return
            }
            Task { @MainActor in
                await self.prepareAndRecord(sessionID: sessionID)
            }
        }
    }

    /// Stops capture and transcribes the recording. `completion` is called
    /// exactly once, with `nil` if nothing usable was captured.
    func stop(completion: @escaping (String?) -> Void) {
        guard state == .recording else {
            completion(nil)
            return
        }
        guard let asrManager else {
            // Shouldn't happen — the model finishes loading before recording
            // starts — but guard rather than crash.
            state = .error("Speech model isn't loaded.")
            completion(nil)
            return
        }

        state = .transcribing
        let sessionID = currentSessionID
        let buffers = bufferAccumulator.drain()

        // Distinguish "the tap never fired" from "the tap fired but every
        // sample was zero" — both surface to the user as a flat waveform and
        // a failed dictation, but they have completely different causes.
        let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let peak = buffers.reduce(Float(0)) { max($0, Self.peakLevel(of: $1)) }
        NSLog("Magpie: dictation — captured \(buffers.count) buffers, \(frames) frames, peak=\(peak)")

        levelMeter.reset()
        teardownEngine()

        Task { @MainActor in
            await self.transcribe(sessionID: sessionID, buffers: buffers, using: asrManager, completion: completion)
        }
    }

    /// Tears down any in-flight session (recording, loading, or
    /// transcribing) without producing a result. Safe to call from any state.
    func cancel() {
        currentSessionID = UUID()
        _ = bufferAccumulator.drain()
        levelMeter.reset()
        stopCompletion = nil
        teardownEngine()
        reset()
    }

    func reset() {
        state = .idle
        recordingStartedAt = nil
    }

    // MARK: - Model loading + recording

    private func prepareAndRecord(sessionID: UUID) async {
        guard sessionID == currentSessionID else { return }

        if asrManager == nil {
            state = .loadingModel
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                guard sessionID == currentSessionID else { return }
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                guard sessionID == currentSessionID else { return }
                asrManager = manager
                NSLog("Magpie: dictation — Parakeet model loaded")
            } catch {
                NSLog("Magpie: dictation — model load failed: \(error.localizedDescription)")
                state = .error("Couldn't load the speech model: \(error.localizedDescription)")
                return
            }
        }

        beginRecording(sessionID: sessionID)
    }

    private func beginRecording(sessionID: UUID) {
        guard sessionID == currentSessionID else { return }

        levelMeter.reset()

        let engine = AVAudioEngine()
        audioEngine = engine

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Record the conditions, not just the outcome. A silent capture has
        // several indistinguishable causes — a denied mic grant, a stale
        // device binding, a device at an unexpected rate — and all of them
        // present as "no audio". These three facts separate them.
        NSLog("""
        Magpie: dictation — mic=\(Microphone.statusDescription) \
        device=\(Self.boundInputDevice(input)) \
        in=\(format.sampleRate)Hz/\(format.channelCount)ch \
        out=\(engine.outputNode.outputFormat(forBus: 0).sampleRate)Hz
        """)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.bufferAccumulator.append(buffer)
            self?.levelMeter.record(Self.rmsLevel(of: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            state = .error("Couldn't start audio capture: \(error.localizedDescription)")
            teardownEngine()
            return
        }

        recordingStartedAt = Date()
        state = .recording
        NSLog("Magpie: dictation — recording started")
    }

    // MARK: - Transcription

    private func transcribe(
        sessionID: UUID,
        buffers: [AVAudioPCMBuffer],
        using asrManager: AsrManager,
        completion: @escaping (String?) -> Void
    ) async {
        guard sessionID == currentSessionID else { return }

        guard !buffers.isEmpty else {
            NSLog("Magpie: dictation — finished with no audio captured")
            state = .error("No speech detected.")
            completion(nil)
            return
        }

        do {
            let converter = AudioConverter()
            var samples: [Float] = []
            for buffer in buffers {
                samples.append(contentsOf: try converter.resampleBuffer(buffer))
            }
            guard sessionID == currentSessionID else { return }

            let decoderLayers = await asrManager.decoderLayerCount
            var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
            let result = try await asrManager.transcribe(samples, decoderState: &decoderState, language: nil)
            guard sessionID == currentSessionID else { return }

            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                NSLog("Magpie: dictation — finished with no speech detected")
                state = .error("No speech detected.")
                completion(nil)
            } else {
                NSLog("Magpie: dictation — finished, transcript length=\(trimmed.count)")
                state = .done(trimmed)
                completion(trimmed)
            }
        } catch {
            NSLog("Magpie: dictation — transcription failed: \(error.localizedDescription)")
            state = .error("Speech recognition failed: \(error.localizedDescription)")
            completion(nil)
        }
    }

    /// Absolute peak sample in a buffer, for diagnosing silent captures.
    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channelData[0][i]))
        }
        return peak
    }

    /// The hardware device the engine's input node actually bound to.
    /// AVAudioEngine does not necessarily pick the device you expect: when the
    /// default input and output differ it binds to a synthesized
    /// `CADefaultDeviceAggregate` rather than the microphone itself, and that
    /// aggregate can be rebuilt or go stale as Bluetooth hardware comes and
    /// goes. The sample rate alone is not enough to identify it.
    private static func boundInputDevice(_ input: AVAudioInputNode) -> String {
        guard let unit = input.audioUnit else { return "<no audio unit>" }

        var deviceID = AudioDeviceID(0)
        var idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &deviceID, &idSize) == noErr
        else { return "<device query failed>" }

        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &nameSize, &name) == noErr,
              let resolved = name?.takeRetainedValue()
        else { return "id=\(deviceID)" }

        return "\(resolved as String) (id=\(deviceID))"
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += samples[i] * samples[i]
        }
        let rms = (sum / Float(frameLength)).squareRoot()

        // Typical speech RMS at a normal mic level sits well under 1.0, so
        // scale up for a visually lively waveform, then clamp.
        return min(rms * 6, 1)
    }

    private func teardownEngine() {
        guard let engine = audioEngine else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
