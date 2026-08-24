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
        Button("Show History  ⌘⇧V") {
            HistoryWindow.shared.show()
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Button("Emoji Picker  ⌘⇧E") {
            EmojiWindow.shared.show()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])

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

        let trusted = Accessibility.isTrusted
        NSLog("Magpie: AX trusted=\(trusted)")
        if !trusted { _ = Accessibility.requestIfNeeded() }
    }
}
