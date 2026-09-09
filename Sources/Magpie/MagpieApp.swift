import SwiftUI
import SwiftData
import AppKit

@main
struct MagpieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Magpie", systemImage: "doc.on.clipboard.fill") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuContent: View {
    var body: some View {
        Button("Cockpit  ⌘␣") {
            ToolChooserWindow.shared.toggle()
        }

        Divider()

        Button("Show History  ⌘⇧V") {
            HistoryWindow.shared.show()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Button("Emoji Picker  ⌘⇧E") {
            EmojiWindow.shared.show()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

        Button("Dictation  ⌘⇧D") {
            DictationWindow.shared.show()
            DictationManager.shared.start()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button("Screen Capture  ⌘⇧X") {
            ScreenCaptureWindow.shared.begin()
        }
        .keyboardShortcut("x", modifiers: [.command, .shift])

        Button("Launch App  ⌘␣ L") {
            LauncherWindow.shared.show()
        }

        Button("Search Files  ⌘␣ S") {
            SpotlightWindow.shared.show()
        }

        Button("R Console  ⌘␣ R") {
            RConsoleWindow.shared.show()
        }

        Button("Audio Devices  ⌘␣ A") {
            AudioWindow.shared.show()
        }

        Button("Talk to Claude  ⌘␣ T") {
            ChatWindow.shared.show()
        }

        Button("GitHub Issue  ⌘␣ G") {
            GitHubWindow.shared.show()
        }

        Divider()

        Button("Clear Unpinned History") {
            HistoryStore.shared.clearAllUnpinned()
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Magpie") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.redirectLogToFileIfHeadless()
        NSLog("Magpie: didFinishLaunching pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSApp.setActivationPolicy(.accessory)

        let cap = UserDefaults.standard.integer(forKey: "historyCap")
        if cap > 0 { HistoryStore.shared.historyCap = cap }

        PasteboardWatcher.shared.start()
        NSLog("Magpie: pasteboard watcher started")

        HotkeyManager.shared.register(.history) {
            NSLog("Magpie: hotkey fired — toggling history window")
            HistoryWindow.shared.toggle()
        }
        HotkeyManager.shared.register(.emoji) {
            NSLog("Magpie: hotkey fired — toggling emoji window")
            EmojiWindow.shared.toggle()
        }
        HotkeyManager.shared.register(.dictation) {
            NSLog("Magpie: hotkey fired — toggling dictation window")
            DictationWindow.shared.toggle()
        }
        HotkeyManager.shared.register(.screenCapture) {
            NSLog("Magpie: hotkey fired — starting screen capture")
            ScreenCaptureWindow.shared.begin()
        }

        // A crash mid-analysis leaves a plaintext screenshot in /tmp.
        ScreenCaptureManager.sweepStaleTempFiles()

        let trusted = Accessibility.isTrusted
        NSLog("Magpie: AX trusted=\(trusted)")
        if !trusted { _ = Accessibility.requestIfNeeded() }

        // The leader: ⌘Space opens the tool chooser. On by default; the
        // Settings toggle flips the same default.
        UserDefaults.standard.register(defaults: [LeaderKey.enabledKey: true])
        LeaderKey.shared.onTrigger = {
            ToolChooserWindow.shared.toggle()
        }
        if UserDefaults.standard.bool(forKey: LeaderKey.enabledKey) {
            LeaderKey.shared.enable()
        }

        // Warm the app index so the first ⌘Space A is instant.
        AppIndex.shared.refreshIfStale()
    }

    /// `magpie://<tool>` toggles a tool from anywhere — a window manager
    /// binding, a script, `open magpie://audio` (again to close). `magpie://cockpit`
    /// toggles the chooser; `magpie://chat?ask=...` always shows the chat and
    /// sends that message straight away.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let key = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // %@ rather than interpolation: a percent-encoded URL inside a
            // format string is parsed as format specifiers.
            NSLog("Magpie: url %@", url.absoluteString)
            if key.isEmpty || key == "cockpit" || key == "chooser" {
                ToolChooserWindow.shared.toggle()
                continue
            }
            guard let tool = Tool.matching(urlKey: key) else {
                NSLog("Magpie: unknown tool in url: %@", key)
                continue
            }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func param(_ name: String) -> String? { query.first { $0.name == name }?.value }
            if tool == .chat, let ask = param("ask"), !ask.isEmpty {
                ChatWindow.shared.show(ask: ask)
            } else if tool == .rconsole, let code = param("run"), !code.isEmpty {
                RConsoleWindow.shared.show(run: code)
            } else if tool == .github, param("repo") != nil || param("title") != nil {
                GitHubWindow.shared.show(repo: param("repo"), title: param("title"), body: param("body"))
            } else {
                tool.toggle()
            }
        }
    }

    /// A menu-bar app launched by LaunchServices has no terminal, and its
    /// NSLog lines do not reliably surface in `log show`. When stderr is not
    /// a TTY, send it to ~/Library/Logs/Magpie/magpie.log (truncated per
    /// launch) so "why didn't ⌘Space work" has an answer.
    private static func redirectLogToFileIfHeadless() {
        guard isatty(STDERR_FILENO) == 0 else { return }
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Magpie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("magpie.log").path
        freopen(path, "w", stderr)
    }
}
