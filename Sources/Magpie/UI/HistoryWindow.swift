import AppKit
import SwiftUI

@MainActor
final class HistoryWindow {
    static let shared = HistoryWindow()

    private var panel: NSPanel?
    private let appState = AppState()

    private init() {}

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        Paster.shared.previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        let targetScreen = Self.screenUnderMouse() ?? NSScreen.main
        if let screen = targetScreen {
            let frame = panel.frame
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSLog("Magpie: panel ordered front, isVisible=\(panel.isVisible)")

        // Fresh state on every show: clear the search, select the latest item,
        // and signal the view to re-focus/re-scroll (onAppear only fires once).
        appState.searchText = ""
        appState.selectedItemID = HistoryStore.shared.items.first?.id
        appState.pasteMode = .paste
        appState.activationToken += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Hide and hand keyboard focus back to the app that was frontmost
    /// before the panel appeared (Esc / click-away path).
    func dismiss() {
        hide()
        if let target = Paster.shared.previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Magpie"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
            .ignoresCycle,
        ]

        let view = HistoryView(
            onPick: { [weak self] item in
                guard let self else { return }
                // Return can be delivered to both the TextField's onSubmit and
                // the hidden shortcut button; only act while still visible.
                guard self.panel?.isVisible == true else { return }
                let mode = self.appState.pasteMode
                self.hide()
                Paster.shared.fire(item, mode: mode)
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(appState)

        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        return panel
    }
}
