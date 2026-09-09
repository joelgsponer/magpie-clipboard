import AppKit
import SwiftUI

@MainActor
final class ChatState: ObservableObject {
    @Published var draft: String = ""
    @Published var activationToken: Int = 0
}

@MainActor
final class ChatWindow {
    static let shared = ChatWindow()

    private var panel: NSPanel?
    private let state = ChatState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    /// `ask` sends a message as soon as the panel is up (the `magpie://chat?ask=`
    /// URL); the draft is left alone otherwise, so a half-typed question
    /// survives an esc.
    func show(ask: String? = nil) {
        previousApp = NSWorkspace.shared.frontmostApplication
        ChatManager.shared.resolveCLI()

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        state.activationToken += 1

        if let ask, !ask.isEmpty {
            ChatManager.shared.send(ask)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func dismiss() {
        hide()
        ChatManager.shared.stopSpeaking()
        if let target = previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel.make(width: 720, height: 600, autosaveName: "MagpieChatPanel", resizable: true)
        panel.minSize = NSSize(width: 520, height: 400)
        let view = ChatView(onClose: { [weak self] in self?.dismiss() })
            .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
