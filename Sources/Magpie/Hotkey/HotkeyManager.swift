import AppKit
import Carbon.HIToolbox

/// Carbon-based global hotkey. Default ⌘⇧V. (No rebind UI in v1.)
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x4D475049 // 'MGPI'
    private static let hotkeyID: UInt32 = 1

    /// Holds a strong ref while registered.
    private static var active: HotkeyManager?

    private init() {}

    func register(onToggle: @escaping () -> Void) {
        self.onTrigger = onToggle
        Self.active = self

        let keyCode: UInt32 = UInt32(kVK_ANSI_V)
        // Cmd+Shift+V. Note: this chord is commonly grabbed by Paste, Maccy,
        // Raycast, Alfred etc., and Carbon RegisterEventHotKey returns noErr even
        // when another app already holds it — so the hotkey may silently not fire.
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        NSLog("Magpie: RegisterEventHotKey status=\(regStatus) (0=ok)")
        if regStatus != noErr { return }
        hotkeyRef = ref

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
            if firedID.signature == HotkeyManager.signature && firedID.id == HotkeyManager.hotkeyID {
                DispatchQueue.main.async {
                    HotkeyManager.active?.onTrigger?()
                }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        NSLog("Magpie: InstallEventHandler status=\(installStatus) (0=ok)")
    }

    func unregister() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotkeyRef = nil
        handlerRef = nil
        Self.active = nil
    }
}
