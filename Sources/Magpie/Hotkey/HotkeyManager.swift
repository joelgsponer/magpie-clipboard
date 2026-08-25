import AppKit
import Carbon.HIToolbox

/// Carbon-based global hotkeys. (No rebind UI in v1.)
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    enum Hotkey: UInt32, CaseIterable {
        case history = 1   // ⌘⇧V
        case emoji = 2     // ⌘⇧E
        case dictation = 3 // ⌘⇧D

        var keyCode: UInt32 {
            switch self {
            case .history: return UInt32(kVK_ANSI_V)
            case .emoji: return UInt32(kVK_ANSI_E)
            case .dictation: return UInt32(kVK_ANSI_D)
            }
        }

        // Note: these chords are commonly grabbed by Paste, Maccy, Raycast,
        // Alfred etc., and Carbon RegisterEventHotKey returns noErr even when
        // another app already holds one — so a hotkey may silently not fire.
        var modifiers: UInt32 {
            UInt32(cmdKey | shiftKey)
        }
    }

    private var hotkeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var handlers: [Hotkey: () -> Void] = [:]

    private static let signature: OSType = 0x4D475049 // 'MGPI'

    /// Holds a strong ref while registered.
    private static var active: HotkeyManager?

    private init() {}

    func register(_ hotkey: Hotkey, action: @escaping () -> Void) {
        handlers[hotkey] = action
        Self.active = self

        let id = EventHotKeyID(signature: Self.signature, id: hotkey.rawValue)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        NSLog("Magpie: RegisterEventHotKey \(String(describing: hotkey)) status=\(regStatus) (0=ok)")
        guard regStatus == noErr, let ref else { return }
        hotkeyRefs.append(ref)
        installHandlerIfNeeded()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var firedID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &firedID
            )
            guard status == noErr else { return status }
            if firedID.signature == HotkeyManager.signature,
               let hotkey = HotkeyManager.Hotkey(rawValue: firedID.id) {
                DispatchQueue.main.async {
                    HotkeyManager.active?.handlers[hotkey]?()
                }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        NSLog("Magpie: InstallEventHandler status=\(installStatus) (0=ok)")
    }

    func unregister() {
        for ref in hotkeyRefs { UnregisterEventHotKey(ref) }
        hotkeyRefs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        handlers.removeAll()
        Self.active = nil
    }
}
