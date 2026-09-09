import AppKit
import SwiftUI

@MainActor
final class SpotlightState: ObservableObject {
    @Published var query: String = ""
    @Published var selectedID: String?
    @Published var activationToken: Int = 0
}

@MainActor
final class SpotlightWindow {
    static let shared = SpotlightWindow()

    private var panel: NSPanel?
    private let state = SpotlightState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        state.query = ""
        state.selectedID = nil
        SpotlightSearch.shared.clear()
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
        let panel = OverlayPanel.make(width: 640, height: 460, autosaveName: "MagpieSpotlightPanel")
        let view = SpotlightView(
            onOpen: { [weak self] r in
                guard self?.panel?.isVisible == true else { return }
                self?.hide()
                NSWorkspace.shared.open(r.url)
            },
            onReveal: { [weak self] r in
                self?.hide()
                NSWorkspace.shared.activateFileViewerSelecting([r.url])
            },
            onCopyPath: { [weak self] r in
                self?.dismiss()
                Paster.shared.copyText(r.url.path)
                HistoryStore.shared.ingest(kind: .text, text: r.url.path, sourceBundleID: "local.magpie")
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
