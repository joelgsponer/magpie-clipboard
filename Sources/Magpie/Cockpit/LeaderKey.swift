import AppKit
import Carbon.HIToolbox

/// The leader chord (⌘Space) that opens the tool chooser.
///
/// Spotlight owns ⌘Space as a system symbolic hotkey, and a Carbon
/// `RegisterEventHotKey` for the same chord loses to it silently. So the
/// primary path is a CGEvent tap at the HID level, inserted at the head of the
/// pipeline: it sees the key-down before the symbolic-hotkey layer does,
/// swallows it, and Spotlight never fires. That tap needs Accessibility trust
/// (which paste-back already requires). If the tap cannot be created, a Carbon
/// hotkey is registered as a fallback and the Settings pane tells the user to
/// turn off Spotlight's shortcut so the fallback wins.
@MainActor
final class LeaderKey {
    static let shared = LeaderKey()

    enum Status: Equatable {
        case disabled
        case eventTap
        case carbonFallback
        case waitingForAccessibility

        var label: String {
            switch self {
            case .disabled: return "Off"
            case .eventTap: return "Active (⌘Space intercepted before Spotlight)"
            case .carbonFallback: return "Fallback hotkey — disable Spotlight's ⌘Space in System Settings › Keyboard › Keyboard Shortcuts › Spotlight"
            case .waitingForAccessibility: return "Waiting for Accessibility permission"
            }
        }
    }

    static let enabledKey = "leaderKeyEnabled"

    private(set) var status: Status = .disabled {
        didSet { onStatusChange?(status) }
    }
    var onStatusChange: ((Status) -> Void)?
    var onTrigger: (() -> Void)?

    /// While the chooser is up it grabs the keyboard through the same tap:
    /// every key-down is offered here first and swallowed when the handler
    /// returns true. This is what makes the chooser modal without it ever
    /// needing to be the key window — a non-activating panel can lose key
    /// status to the frontmost app (Chrome reclaims it within milliseconds),
    /// and the letter would then land in the user's document.
    var keyInterceptor: ((NSEvent) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var carbonRef: EventHotKeyRef?

    private init() {}

    var isEnabled: Bool { status != .disabled }

    func enable() {
        guard status == .disabled else { return }
        if installTap() {
            status = .eventTap
            return
        }
        if Accessibility.isTrusted {
            // Trusted but the tap still failed (rare): fall back.
            installCarbonFallback()
            status = .carbonFallback
        } else {
            status = .waitingForAccessibility
            scheduleRetry()
        }
    }

    func disable() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
        if let carbonRef {
            UnregisterEventHotKey(carbonRef)
        }
        carbonRef = nil
        status = .disabled
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: leaderTapCallback,
            userInfo: userInfo
        ) else {
            NSLog("Magpie: leader event tap could not be created (AX trusted=\(Accessibility.isTrusted))")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        NSLog("Magpie: leader event tap installed")
        return true
    }

    /// macOS disables a tap that takes too long or when the user presses
    /// keys during a hang. Re-arm rather than losing the leader silently.
    fileprivate func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Magpie: leader event tap re-enabled")
    }

    fileprivate func fire() {
        NSLog("Magpie: leader fired")
        onTrigger?()
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status == .waitingForAccessibility else { return }
                guard Accessibility.isTrusted else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                if self.installTap() {
                    self.status = .eventTap
                } else {
                    self.installCarbonFallback()
                    self.status = .carbonFallback
                }
            }
        }
    }

    // MARK: - Carbon fallback

    private static let signature: OSType = 0x4D47504C // 'MGPL'
    private static var fallbackHandler: EventHandlerRef?

    private func installCarbonFallback() {
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &ref)
        NSLog("Magpie: leader Carbon fallback RegisterEventHotKey status=\(status)")
        carbonRef = ref

        guard Self.fallbackHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return OSStatus(eventNotHandledErr) }
            var firedID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &firedID
            )
            guard status == noErr, firedID.signature == LeaderKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { LeaderKey.shared.fire() }
            return noErr
        }, 1, &spec, nil, &Self.fallbackHandler)
    }
}

/// C callback: must not capture context, so `LeaderKey` rides in userInfo.
/// The run-loop source lives on the main run loop, so this runs on the main
/// thread and can hop onto the main actor without a dispatch.
private func leaderTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let leader = Unmanaged<LeaderKey>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { leader.reenableTap() }
        return Unmanaged.passUnretained(event)

    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == Int64(kVK_Space), modifiers == .maskCommand {
            if !isRepeat {
                DispatchQueue.main.async { leader.fire() }
            }
            // Swallow: nothing downstream (Spotlight included) sees ⌘Space.
            return nil
        }

        let consumed: Bool = MainActor.assumeIsolated {
            guard let interceptor = leader.keyInterceptor else { return false }
            if isRepeat { return true }
            guard let nsEvent = NSEvent(cgEvent: event) else { return true }
            return interceptor(nsEvent)
        }
        return consumed ? nil : Unmanaged.passUnretained(event)

    default:
        return Unmanaged.passUnretained(event)
    }
}
