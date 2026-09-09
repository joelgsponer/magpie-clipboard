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

        Button("Launch App  ⌘␣ A") {
            LauncherWindow.shared.show()
        }

        Button("Search Files  ⌘␣ S") {
            SpotlightWindow.shared.show()
        }

        Button("Calculator  ⌘␣ M") {
            CalculatorWindow.shared.show()
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
}
