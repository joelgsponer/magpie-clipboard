import AppKit
import SwiftUI

@MainActor
final class LauncherState: ObservableObject {
    @Published var query: String = ""
    @Published var selectedID: String?
    @Published var activationToken: Int = 0
}

@MainActor
final class LauncherWindow {
    static let shared = LauncherWindow()

    private var panel: NSPanel?
    private let state = LauncherState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        AppIndex.shared.refreshIfStale()

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        state.query = ""
        state.selectedID = nil
        state.activationToken += 1
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
        let panel = OverlayPanel.make(width: 600, height: 440, autosaveName: "MagpieLauncherPanel")
        let view = LauncherView(
            onLaunch: { [weak self] app in
                guard self?.panel?.isVisible == true else { return }
                self?.hide()
                AppIndex.shared.launch(app)
            },
            onReveal: { [weak self] app in
                self?.hide()
                AppIndex.shared.reveal(app)
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
