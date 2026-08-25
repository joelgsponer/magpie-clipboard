import AppKit
import SwiftUI

/// Bumped on every show so EmojiView resets (panel is hidden, not torn down).
@MainActor
final class EmojiActivator: ObservableObject {
    @Published var token: Int = 0
}

@MainActor
final class EmojiWindow {
    static let shared = EmojiWindow()

    private var panel: NSPanel?
    private let activator = EmojiActivator()

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

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        activator.token += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Hide and hand keyboard focus back to the previously frontmost app.
    func dismiss() {
        hide()
        if let target = Paster.shared.previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Magpie Emoji"
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
        PanelPositioning.applyPersistentPosition(to: panel, autosaveName: "MagpieEmojiPanel")

        let view = EmojiView(
            onPick: { [weak self] entry, copyOnly, type in
                guard let self else { return }
                guard self.panel?.isVisible == true else { return }
                self.hide()
                EmojiStore.shared.record(entry.char)
                if copyOnly {
                    Paster.shared.copyText(entry.char)
                } else {
                    Paster.shared.insertText(entry.char, mode: type ? .type : .paste)
                }
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(activator)

        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        return panel
    }
}
