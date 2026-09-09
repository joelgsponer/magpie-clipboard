import AppKit
import SwiftUI

@MainActor
final class ToolChooserState: ObservableObject {
    @Published var highlighted: Tool? = nil
    @Published var activationToken: Int = 0
}

/// The on-screen tool chooser behind ⌘Space.
///
/// Deliberately a *non-activating* panel, so Magpie never becomes the
/// frontmost app while it is up. That keeps `NSWorkspace.frontmostApplication`
/// pointing at the user's app, which is what every tool's show() captures as
/// the paste-back target; activating here would make every tool paste into
/// Magpie itself.
///
/// Keys reach it one of two ways. With the leader event tap active (the
/// normal case) the tap hands every key-down to `handle` before any app sees
/// it — the panel is never key, nothing can steal focus from it, and no
/// keystroke leaks. On the Carbon fallback there is no tap, so the panel
/// makes itself key and listens with a local monitor instead; that path can
/// lose key status to a busy frontmost app, which is why it is the fallback.
@MainActor
final class ToolChooserWindow {
    static let shared = ToolChooserWindow()

    private var panel: NSPanel?
    private let state = ToolChooserState()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = PanelPositioning.screenUnderMouse() ?? NSScreen.main {
            var origin = PanelPositioning.centerOrigin(for: panel.frame, on: screen)
            // Sit a little above centre, like a game HUD, not dead centre.
            origin.y += screen.visibleFrame.height * 0.08
            panel.setFrameOrigin(origin)
        }

        state.highlighted = nil
        state.activationToken += 1

        if LeaderKey.shared.status == .eventTap {
            LeaderKey.shared.keyInterceptor = { [weak self] event in
                self?.handle(event) ?? false
            }
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
            installMonitors()
        }
        installClickAwayMonitor()
        NSLog("Magpie: chooser shown via \(LeaderKey.shared.status == .eventTap ? "tap" : "key window") frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    func hide() {
        LeaderKey.shared.keyInterceptor = nil
        removeMonitors()
        removeClickAwayMonitor()
        panel?.orderOut(nil)
    }

    private func pick(_ tool: Tool) {
        hide()
        // Let the orderOut settle before the tool activates the app.
        DispatchQueue.main.async {
            tool.open()
        }
    }

    // MARK: - Click-away

    private var clickAwayMonitor: Any?

    /// A click anywhere outside the panel dismisses it, whichever app gets
    /// the click. (Clicks inside are delivered to the panel's own views.)
    private func installClickAwayMonitor() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) { self.hide() }
            }
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
    }

    // MARK: - Keys (Carbon-fallback path)

    private func installMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53, 49: // esc, space (space again closes — a second ⌘Space is swallowed by the tap and toggles)
            hide()
            return true
        case 36, 76: // return, keypad enter
            if let tool = state.highlighted { pick(tool) }
            return true
        case 123: moveHighlight(by: -1); return true
        case 124: moveHighlight(by: 1); return true
        case 48: // tab
            moveHighlight(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        default:
            break
        }
        // Letters work with or without ⌘ still held: "⌘Space, C" and
        // "⌘Space then ⌘C" (never let go of ⌘) both open the clipboard.
        // Any other key cancels, leader-key style — the chooser must never
        // sit there eating keystrokes meant for the app underneath.
        guard let ch = event.charactersIgnoringModifiers?.first,
              let tool = Tool.matching(key: ch) else {
            hide()
            return true
        }
        pick(tool)
        return true
    }

    private func moveHighlight(by offset: Int) {
        let all = Tool.allCases
        guard let current = state.highlighted, let idx = all.firstIndex(of: current) else {
            state.highlighted = offset > 0 ? all.first : all.last
            return
        }
        let next = (idx + offset + all.count) % all.count
        state.highlighted = all[next]
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 230),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
            .ignoresCycle,
        ]

        let view = ToolChooserView(
            onPick: { [weak self] tool in self?.pick(tool) },
            onHover: { [weak self] tool in self?.state.highlighted = tool }
        )
        .environmentObject(state)

        let host = KeyableHostingView(rootView: view)
        panel.contentView = host
        // One card per tool: let the content dictate the panel size.
        panel.setContentSize(host.fittingSize)
        return panel
    }
}

/// Borderless panels refuse key status unless told otherwise.
private final class KeyableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

/// Borderless + nonactivating panels return false for canBecomeKey by
/// default, which would leave the chooser unable to receive its keystroke.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
