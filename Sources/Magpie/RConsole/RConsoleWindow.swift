import AppKit
import SwiftUI

@MainActor
final class RConsoleState: ObservableObject {
    @Published var input: String = ""
    @Published var historyIndex: Int? = nil
    @Published var activationToken: Int = 0
}

@MainActor
final class RConsoleWindow {
    static let shared = RConsoleWindow()

    private var panel: NSPanel?
    private let state = RConsoleState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    /// `run` executes code as soon as the panel is up (the `magpie://r?run=`
    /// URL). The session persists while Magpie runs.
    func show(run: String? = nil) {
        previousApp = NSWorkspace.shared.frontmostApplication
        RSession.shared.startIfNeeded()

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        state.activationToken += 1

        if let run, !run.isEmpty {
            RSession.shared.run(run)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func dismiss() {
        hide()
        if let target = previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel.make(width: 860, height: 560, autosaveName: "MagpieRConsolePanel", resizable: true)
        panel.minSize = NSSize(width: 600, height: 380)
        let view = RConsoleView(onClose: { [weak self] in self?.dismiss() })
            .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
