import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    let transport: UInt32

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeThunderbolt: return "display"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform.path"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "iphone"
        default: return "speaker.wave.2"
        }
    }

    var transportLabel: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity"
        default: return ""
        }
    }
}

/// CoreAudio device list plus the two system defaults and their volume.
/// Everything is read synchronously on the main thread — the HAL answers
/// these from cache — and listeners keep the published state live while
/// the panel is up (a headset connecting, the keyboard volume keys).
@MainActor
final class AudioDevices: ObservableObject {
    static let shared = AudioDevices()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var defaultOutput: AudioDeviceID?
    @Published private(set) var defaultInput: AudioDeviceID?
    /// nil when the default device exposes no settable volume (HDMI, AirPlay…).
    @Published private(set) var outputVolume: Float?
    @Published private(set) var outputMuted: Bool = false
    @Published private(set) var inputVolume: Float?

    var outputs: [AudioDevice] { devices.filter(\.hasOutput) }
    var inputs: [AudioDevice] { devices.filter(\.hasInput) }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private var systemListenersInstalled = false
    private var volumeListenedDevices: [AudioDeviceID] = []

    private init() {}

    // MARK: - Public

    func refresh() {
        installSystemListenersIfNeeded()

        let ids: [AudioDeviceID] = Self.array(Self.systemObject, kAudioHardwarePropertyDevices) ?? []
        devices = ids.compactMap { id in
            let inputs = Self.channelCount(id, scope: kAudioObjectPropertyScopeInput)
            let outputs = Self.channelCount(id, scope: kAudioObjectPropertyScopeOutput)
            guard inputs > 0 || outputs > 0 else { return nil }
            let name: String = Self.string(id, kAudioObjectPropertyName) ?? "Device \(id)"
            let transport: UInt32 = Self.value(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioDevice(id: id, name: name, hasInput: inputs > 0, hasOutput: outputs > 0, transport: transport)
        }

        defaultOutput = Self.value(Self.systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        defaultInput = Self.value(Self.systemObject, kAudioHardwarePropertyDefaultInputDevice)
        refreshLevels()
        installVolumeListeners()
    }

    func setDefaultOutput(_ id: AudioDeviceID) {
        Self.set(Self.systemObject, kAudioHardwarePropertyDefaultOutputDevice, id)
        // Alerts and UI sounds follow the same choice, as System Settings does.
        Self.set(Self.systemObject, kAudioHardwarePropertyDefaultSystemOutputDevice, id)
        refresh()
    }

    func setDefaultInput(_ id: AudioDeviceID) {
        Self.set(Self.systemObject, kAudioHardwarePropertyDefaultInputDevice, id)
        refresh()
    }

    func setOutputVolume(_ v: Float) {
        guard let id = defaultOutput else { return }
        Self.setVolume(id, scope: kAudioObjectPropertyScopeOutput, max(0, min(1, v)))
        refreshLevels()
    }

    func setInputVolume(_ v: Float) {
        guard let id = defaultInput else { return }
        Self.setVolume(id, scope: kAudioObjectPropertyScopeInput, max(0, min(1, v)))
        refreshLevels()
    }

    func nudgeOutputVolume(_ delta: Float) {
        guard let v = outputVolume else { return }
        setOutputVolume(v + delta)
    }

    func nudgeInputVolume(_ delta: Float) {
        guard let v = inputVolume else { return }
        setInputVolume(v + delta)
    }

    func toggleOutputMute() {
        guard let id = defaultOutput else { return }
        let current: UInt32 = Self.value(id, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput) ?? 0
        Self.set(id, kAudioDevicePropertyMute, UInt32(current == 0 ? 1 : 0), scope: kAudioObjectPropertyScopeOutput)
        refreshLevels()
    }

    // MARK: - Levels

    private func refreshLevels() {
        if let id = defaultOutput {
            outputVolume = Self.volume(id, scope: kAudioObjectPropertyScopeOutput)
            let muted: UInt32 = Self.value(id, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput) ?? 0
            outputMuted = muted != 0
        } else {
            outputVolume = nil
            outputMuted = false
        }
        inputVolume = defaultInput.flatMap { Self.volume($0, scope: kAudioObjectPropertyScopeInput) }
    }

    // MARK: - Listeners

    private func installSystemListenersIfNeeded() {
        guard !systemListenersInstalled else { return }
        systemListenersInstalled = true
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(Self.systemObject, &addr, .main) { [weak self] _, _ in
                self?.refresh()
            }
        }
    }

    /// Volume/mute listeners live on the *current* default devices and move
    /// with them, so the sliders track the keyboard volume keys.
    private func installVolumeListeners() {
        let wanted = [defaultOutput, defaultInput].compactMap { $0 }
        guard wanted != volumeListenedDevices else { return }
        for id in volumeListenedDevices { Self.forEachLevelAddress(id) { addr in
            var a = addr
            AudioObjectRemovePropertyListenerBlock(id, &a, .main, Self.levelBlock)
        } }
        volumeListenedDevices = wanted
        for id in wanted { Self.forEachLevelAddress(id) { addr in
            var a = addr
            AudioObjectAddPropertyListenerBlock(id, &a, .main, Self.levelBlock)
        } }
    }

    private static let levelBlock: AudioObjectPropertyListenerBlock = { _, _ in
        Task { @MainActor in AudioDevices.shared.refreshLevels() }
    }

    private static func forEachLevelAddress(_ id: AudioDeviceID, _ body: (AudioObjectPropertyAddress) -> Void) {
        for scope in [kAudioObjectPropertyScopeOutput, kAudioObjectPropertyScopeInput] {
            for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
                for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
                    if AudioObjectHasProperty(id, &addr) { body(addr) }
                }
            }
        }
    }

    // MARK: - Volume plumbing

    /// Main element first; many devices only expose per-channel volume, in
    /// which case channel 1 stands in (and sets go to channels 1 and 2).
    private static func volumeElement(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> AudioObjectPropertyElement? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(id, &addr),
               AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue {
                return element
            }
        }
        return nil
    }

    private static func volume(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Float? {
        guard let element = volumeElement(id, scope: scope) else { return nil }
        return value(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
    }

    private static func setVolume(_ id: AudioDeviceID, scope: AudioObjectPropertyScope, _ v: Float) {
        guard let element = volumeElement(id, scope: scope) else { return }
        if element == kAudioObjectPropertyElementMain {
            set(id, kAudioDevicePropertyVolumeScalar, v, scope: scope, element: element)
        } else {
            for channel: AudioObjectPropertyElement in [1, 2] {
                set(id, kAudioDevicePropertyVolumeScalar, v, scope: scope, element: channel)
            }
        }
    }

    // MARK: - Property helpers

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func value<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, ptr) == noErr else { return nil }
        return ptr.move()
    }

    private static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [T]? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<T>.size
        return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer.baseAddress!)
            initialized = status == noErr ? count : 0
        }
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func set<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ newValue: T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var v = newValue
        let status = AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v)
        if status != noErr { NSLog("Magpie: audio set \(selector) on \(object) failed: \(status)") }
    }
}
