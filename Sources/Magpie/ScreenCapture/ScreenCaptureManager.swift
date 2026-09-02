import AppKit
import Foundation

/// What the panel can offer the user to fix a failure, when there is something
/// concrete to offer.
enum CaptureRecovery: Equatable {
    case screenRecordingSettings
    case magpieSettings
}

enum ScreenCaptureState: Equatable {
    case idle
    /// Crosshair is up. The panel must NOT be visible in this state.
    case selectingRegion
    case analysing
    case done(ScreenCaptureResult)
    case error(String, CaptureRecovery?)
}

struct ScreenCaptureResult: Equatable {
    /// May be empty — a photo or an unlabelled chart has no text to read.
    let extractedText: String
    let context: String
    let imageData: Data
    let pixelSize: CGSize
    let costUSD: Double?
}

/// Captures a screen region and sends it to `claude -p` for transcription plus
/// a context description.
///
/// Owns only the capture/analysis pipeline; committing the result to the
/// pasteboard and history is the caller's job (see ScreenCaptureWindow) —
/// the same split DictationManager uses.
///
/// Unlike dictation, the work here is two child processes, so the session-token
/// pattern is necessary but not sufficient: a discarded token still leaves
/// `claude` running, burning tokens and holding the temp file. `cancel()`
/// therefore terminates the process as well as rotating the token.
@MainActor
final class ScreenCaptureManager: ObservableObject {
    static let shared = ScreenCaptureManager()

    @Published private(set) var state: ScreenCaptureState = .idle
    @Published private(set) var analysisStartedAt: Date?

    /// Invalidates stray callbacks from a session already cancelled or superseded.
    private var currentSessionID = UUID()
    private var runningProcess: Process?
    private var timeoutWork: DispatchWorkItem?
    private var tempURL: URL?

    /// Measured range for real captures was ~7-58s; 90 is generous enough not
    /// to kill a slow dense-image analysis, short enough that a hang doesn't
    /// strand the panel.
    private let timeout: TimeInterval = 90

    private init() {}

    /// Box so pipe-reader threads can hand data back without tripping Sendable.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    // MARK: - Pipeline

    /// Runs preflight, then the crosshair, then the analysis.
    ///
    /// `presentPanel` is invoked at the first moment the panel should become
    /// visible — either a preflight failure, or the start of analysis. It is
    /// deliberately never called during region selection, because the crosshair
    /// owns the screen and an activating panel would fight it for focus.
    func start(presentPanel: @escaping () -> Void) {
        guard state == .idle else { return }

        // Resolve the CLI before the crosshair, not after: better to fail now
        // than to make the user select a region and only then say it's missing.
        guard let claudePath = ClaudeCLI.resolve() else {
            state = .error(
                "Couldn't find the `claude` command. Install Claude Code, or set its full path in Magpie Settings → Screen Capture.",
                .magpieSettings
            )
            presentPanel()
            return
        }

        guard ScreenRecording.isTrusted else {
            ScreenRecording.requestIfNeeded()
            state = .error(
                "Magpie needs Screen Recording permission. Enable it, then quit and reopen Magpie — the grant only takes effect on relaunch.",
                .screenRecordingSettings
            )
            presentPanel()
            return
        }

        let sessionID = currentSessionID
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-capture-\(UUID().uuidString).png")
        tempURL = url

        state = .selectingRegion

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i crosshair, -o no window shadow, -r no DPI metadata, -x no shutter
        // sound. Deliberately not -c: that writes the pasteboard and would trip
        // PasteboardWatcher into ingesting a duplicate.
        proc.arguments = ["-i", "-o", "-r", "-x", url.path]
        proc.standardInput = FileHandle.nullDevice
        runningProcess = proc

        do {
            try proc.run()
        } catch {
            runningProcess = nil
            cleanupTempFile()
            state = .error("Couldn't start screencapture: \(error.localizedDescription)", nil)
            presentPanel()
            return
        }

        DispatchQueue.global().async {
            proc.waitUntilExit()
            Task { @MainActor in
                self.selectionFinished(
                    sessionID: sessionID,
                    imageURL: url,
                    claudePath: claudePath,
                    presentPanel: presentPanel
                )
            }
        }
    }

    private func selectionFinished(
        sessionID: UUID,
        imageURL: URL,
        claudePath: String,
        presentPanel: @escaping () -> Void
    ) {
        guard sessionID == currentSessionID else { return }
        runningProcess = nil

        let fm = FileManager.default
        let size = (try? imageURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        // Esc / no selection. Test the file, not the exit code: screencapture's
        // status on cancel has shifted across macOS releases, but "no file, or
        // an empty one" is invariant.
        guard fm.fileExists(atPath: imageURL.path), size > 0 else {
            cleanupTempFile()
            state = .idle
            return
        }

        // A plaintext screenshot on disk, however briefly. Narrow it to the user.
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)

        guard let data = try? Data(contentsOf: imageURL) else {
            cleanupTempFile()
            state = .error("Couldn't read the captured image.", nil)
            presentPanel()
            return
        }

        let pixelSize = NSImage(data: data)?.size ?? .zero

        analysisStartedAt = Date()
        state = .analysing
        presentPanel()

        analyse(
            sessionID: sessionID,
            claudePath: claudePath,
            imageURL: imageURL,
            imageData: data,
            pixelSize: pixelSize
        )
    }

    private func analyse(
        sessionID: UUID,
        claudePath: String,
        imageURL: URL,
        imageData: Data,
        pixelSize: CGSize
    ) {
        let proc = ClaudeCLI.makeProcess(
            executable: claudePath,
            imagePath: imageURL.path,
            workingDirectory: imageURL.deletingLastPathComponent()
        )
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        runningProcess = proc

        do {
            try proc.run()
        } catch {
            runningProcess = nil
            analysisStartedAt = nil
            cleanupTempFile()
            state = .error("Couldn't run claude: \(error.localizedDescription)", .magpieSettings)
            return
        }

        // Drain both pipes concurrently and only then wait. stderr is chatty
        // (connector warnings, MCP notices) and a full 64 KB pipe buffer would
        // deadlock the child against a waitUntilExit that never returns.
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let work = DispatchWorkItem {
            Task { @MainActor [weak self] in
                guard let self, sessionID == self.currentSessionID else { return }
                self.handleTimeout()
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        DispatchQueue.global().async {
            group.wait()
            proc.waitUntilExit()
            let status = proc.terminationStatus
            let out = outBox.data
            let err = errBox.data
            Task { @MainActor in
                self.analysisFinished(
                    sessionID: sessionID,
                    stdout: out,
                    stderr: err,
                    status: status,
                    imageData: imageData,
                    pixelSize: pixelSize
                )
            }
        }
    }

    private func analysisFinished(
        sessionID: UUID,
        stdout: Data,
        stderr: Data,
        status: Int32,
        imageData: Data,
        pixelSize: CGSize
    ) {
        guard sessionID == currentSessionID else { return }
        timeoutWork?.cancel()
        timeoutWork = nil
        runningProcess = nil
        analysisStartedAt = nil
        cleanupTempFile()

        // SIGTERM from our own cancel(). The rotated token normally catches
        // this first, but don't risk surfacing a spurious error if it doesn't.
        if status == 143 {
            state = .idle
            return
        }

        switch ClaudeCLI.parse(stdout: stdout, stderr: stderr, status: status) {
        case .success(let analysis):
            NSLog("Magpie: capture — done, text=\(analysis.text.count) chars, cost=\(analysis.costUSD.map { String(format: "$%.4f", $0) } ?? "n/a")")
            state = .done(ScreenCaptureResult(
                extractedText: analysis.text,
                context: analysis.context,
                imageData: imageData,
                pixelSize: pixelSize,
                costUSD: analysis.costUSD
            ))
        case .failure(let message):
            NSLog("Magpie: capture — failed: \(message)")
            state = .error(message, nil)
        }
    }

    private func handleTimeout() {
        terminateRunningProcess()
        analysisStartedAt = nil
        cleanupTempFile()
        state = .error("Analysis timed out after \(Int(timeout))s. If this keeps happening, run `claude` once in a terminal to check it's signed in.", nil)
    }

    // MARK: - Cancellation

    /// Tears down any in-flight capture or analysis without producing a result.
    /// Safe to call from any state.
    func cancel() {
        currentSessionID = UUID()
        timeoutWork?.cancel()
        timeoutWork = nil
        terminateRunningProcess()
        cleanupTempFile()
        analysisStartedAt = nil
        state = .idle
    }

    func reset() {
        state = .idle
        analysisStartedAt = nil
    }

    /// SIGTERM, then SIGKILL if it's still alive two seconds later. `claude`
    /// exits 143 on SIGTERM and takes its own child tree down with it; the same
    /// slot holds `screencapture` during selection, so this also dismisses the
    /// crosshair.
    private func terminateRunningProcess() {
        guard let proc = runningProcess else { return }
        if proc.isRunning {
            proc.terminate()
            let pid = proc.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if proc.isRunning { kill(pid, SIGKILL) }
            }
        }
        runningProcess = nil
    }

    // MARK: - Temp files

    private func cleanupTempFile() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempURL = nil
    }

    /// A crash mid-analysis leaks a plaintext screenshot into the temp
    /// directory. Called once at launch to clear anything older than an hour.
    static func sweepStaleTempFiles() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-3600)
        for url in entries where url.lastPathComponent.hasPrefix("magpie-capture-") {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
