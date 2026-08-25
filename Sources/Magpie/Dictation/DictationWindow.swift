import AppKit
import SwiftUI

@MainActor
final class DictationWindow {
    static let shared = DictationWindow()

    private var panel: NSPanel?

    private init() {}

    func toggle() {
        switch DictationManager.shared.state {
        case .idle:
            show()
            DictationManager.shared.start()
        case .recording:
            DictationManager.shared.stop { [weak self] transcript in
                self?.commit(transcript)
            }
        case .requestingAccess, .loadingModel, .transcribing:
            break
        case .done, .error:
            dismiss()
        }
    }

    func show() {
        Paster.shared.previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Cancel any in-flight recording, hide, and hand keyboard focus back to
    /// the app that was frontmost before the panel appeared.
    func dismiss() {
        DictationManager.shared.cancel()
        hide()
        if let target = Paster.shared.previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    /// Writes the finished transcript to the pasteboard and clipboard
    /// history. Mirrors Paster.copyText's convention: the pasteboard write
    /// suppresses PasteboardWatcher's own poll-based ingest, and we record
    /// history explicitly ourselves.
    private func commit(_ transcript: String?) {
        guard let text = transcript, !text.isEmpty else { return }
        Paster.shared.copyText(text)
        HistoryStore.shared.ingest(kind: .text, text: text, sourceBundleID: Bundle.main.bundleIdentifier)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Magpie Dictation"
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
        PanelPositioning.applyPersistentPosition(to: panel, autosaveName: "MagpieDictationPanel")

        let view = DictationView(onClose: { [weak self] in self?.dismiss() })

        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        return panel
    }
}
