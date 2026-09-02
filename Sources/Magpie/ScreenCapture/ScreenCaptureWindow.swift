import AppKit
import SwiftUI

@MainActor
final class ScreenCaptureWindow {
    static let shared = ScreenCaptureWindow()

    private var panel: NSPanel?

    /// Captured before the crosshair goes up, and re-asserted at commit time.
    /// `Paster.previousApp` is a single global slot written by every panel's
    /// show(), so a ⌘⇧V during a long analysis would otherwise redirect our
    /// paste into the history panel's target instead of the original app.
    private var stashedPreviousApp: NSRunningApplication?

    private static let disclosureKey = "captureDisclosureAccepted"

    private init() {}

    /// Entry point for the ⌘⇧X hotkey and the menu item.
    ///
    /// Note the ordering is inverted relative to DictationWindow, which shows
    /// its panel and then starts work. Here the panel must stay hidden until
    /// analysis begins: `screencapture -i` takes over the screen, and an
    /// activating panel would fight the crosshair for focus.
    func begin() {
        switch ScreenCaptureManager.shared.state {
        case .idle:
            guard confirmFirstRunIfNeeded() else { return }

            // Before the crosshair, not after: selection is unbounded in time,
            // and the overlay may change the frontmost app.
            stashedPreviousApp = NSWorkspace.shared.frontmostApplication
            Paster.shared.previousApp = stashedPreviousApp

            ScreenCaptureManager.shared.start { [weak self] in
                self?.show()
            }

        case .selectingRegion, .analysing:
            // Inert while work is in flight — a second press would otherwise
            // spawn a second process pair against a single cancellable slot.
            break

        case .done, .error:
            dismiss()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Cancel any in-flight capture, hide, and hand focus back.
    func dismiss() {
        ScreenCaptureManager.shared.cancel()
        hide()
        restoreFocus()
    }

    private func restoreFocus() {
        guard let target = stashedPreviousApp else { return }
        NSApp.yieldActivation(to: target)
        target.activate()
    }

    // MARK: - First-run disclosure

    /// Magpie is otherwise a local-only app, so the first capture asks
    /// explicitly before anything leaves the machine.
    private func confirmFirstRunIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.disclosureKey) else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Send screen captures to Claude?"
        alert.informativeText = """
        Screen Capture sends the region you select to Anthropic's API via the \
        `claude` command, which returns the text it contains plus a short \
        description of what it is.

        Unlike Magpie's dictation, this does not run on your Mac. Anything \
        visible in the region — including passwords, messages or confidential \
        information — is transmitted. Each capture also costs roughly $0.04 \
        against your Claude account.

        You can turn this off again in Magpie Settings.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Screen Capture")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        defaults.set(true, forKey: Self.disclosureKey)
        return true
    }

    // MARK: - Commit

    /// Writes the chosen text to the pasteboard and records the capture in
    /// history. Mirrors DictationWindow.commit: going through Paster sets
    /// PasteboardWatcher.skipNextChangeCount, so the poll-based watcher won't
    /// ingest our own write as a duplicate.
    private func commit(_ result: ScreenCaptureResult, mode: CaptureCommitMode, paste: Bool) {
        let text = Self.commitString(result, mode: mode)

        // Record the capture regardless — even a text-free image is worth
        // keeping, since the context makes it findable.
        HistoryStore.shared.ingest(
            kind: .image,
            imageData: result.imageData,
            sourceBundleID: Bundle.main.bundleIdentifier,
            extractedText: result.extractedText.isEmpty ? nil : result.extractedText,
            imageContext: result.context
        )

        hide()
        ScreenCaptureManager.shared.reset()

        guard !text.isEmpty else {
            restoreFocus()
            return
        }

        // Re-assert the target in case another panel overwrote the shared slot
        // while the analysis was running.
        Paster.shared.previousApp = stashedPreviousApp

        if paste {
            // insertText runs its own activation dance, so don't restore focus
            // here — that would race the synthetic ⌘V.
            Paster.shared.insertText(text, mode: .paste)
        } else {
            Paster.shared.copyText(text)
            restoreFocus()
        }
    }

    static func commitString(_ result: ScreenCaptureResult, mode: CaptureCommitMode) -> String {
        switch mode {
        case .textOnly:
            return result.extractedText
        case .withContext:
            guard !result.extractedText.isEmpty else { return result.context }
            return result.extractedText + "\n\n---\n" + result.context
        }
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Magpie Screen Capture"
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
        PanelPositioning.applyPersistentPosition(to: panel, autosaveName: "MagpieScreenCapturePanel")

        let view = ScreenCaptureView(
            onClose: { [weak self] in self?.dismiss() },
            onCommit: { [weak self] result, mode, paste in
                self?.commit(result, mode: mode, paste: paste)
            }
        )

        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        return panel
    }
}
