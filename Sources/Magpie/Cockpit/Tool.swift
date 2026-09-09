import AppKit
import SwiftUI

/// Everything the cockpit can open. Declaration order is the order the
/// chooser shows them in, left to right.
enum Tool: String, CaseIterable, Identifiable {
    case clipboard
    case emoji
    case dictation
    case capture
    case apps
    case search
    case rconsole
    case audio
    case chat
    case github

    var id: String { rawValue }

    /// The key that picks this tool from the chooser.
    var letter: Character {
        switch self {
        case .clipboard: return "c"
        case .emoji: return "e"
        case .dictation: return "d"
        case .capture: return "x"
        case .apps: return "l"
        case .search: return "s"
        case .rconsole: return "r"
        case .audio: return "a"
        case .chat: return "t"
        case .github: return "g"
        }
    }

    /// Extra keys that also pick this tool (not shown on the badge).
    var aliases: Set<Character> {
        switch self {
        case .clipboard: return ["v"]
        case .apps: return ["p"]
        case .search: return ["f"]
        case .rconsole: return ["m", "=", "k"]
        case .audio: return ["o", "u"]
        case .chat: return ["i", "q"]
        case .github: return ["h"]
        default: return []
        }
    }

    var name: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji"
        case .dictation: return "Dictate"
        case .capture: return "Capture"
        case .apps: return "Launch"
        case .search: return "Search"
        case .rconsole: return "R"
        case .audio: return "Audio"
        case .chat: return "Talk"
        case .github: return "GitHub"
        }
    }

    var subtitle: String {
        switch self {
        case .clipboard: return "history"
        case .emoji: return "picker"
        case .dictation: return "speech to text"
        case .capture: return "screen region"
        case .apps: return "apps"
        case .search: return "files"
        case .rconsole: return "console · plots"
        case .audio: return "in / out"
        case .chat: return "Claude chat"
        case .github: return "new issue"
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard.fill"
        case .emoji: return "face.smiling.fill"
        case .dictation: return "waveform"
        case .capture: return "viewfinder"
        case .apps: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        case .rconsole: return "r.square.fill"
        case .audio: return "speaker.wave.2.fill"
        case .chat: return "text.bubble.fill"
        case .github: return "smallcircle.filled.circle"
        }
    }

    /// The system-wide chord that opens the tool without the leader, if any.
    var directHotkey: String? {
        switch self {
        case .clipboard: return "⌘⇧V"
        case .emoji: return "⌘⇧E"
        case .dictation: return "⌘⇧D"
        case .capture: return "⌘⇧X"
        default: return nil
        }
    }

    var tint: Color {
        switch self {
        case .clipboard: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .emoji: return Color(red: 1.0, green: 0.78, blue: 0.25)
        case .dictation: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .capture: return Color(red: 0.62, green: 0.48, blue: 1.0)
        case .apps: return Color(red: 0.30, green: 0.82, blue: 0.62)
        case .search: return Color(red: 0.95, green: 0.55, blue: 0.25)
        case .rconsole: return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .audio: return Color(red: 0.93, green: 0.42, blue: 0.68)
        case .chat: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .github: return Color(red: 0.55, green: 0.52, blue: 0.95)
        }
    }

    /// Resolves the `magpie://<tool>` URL host: the case name, the display
    /// name, or a handful of synonyms.
    static func matching(urlKey: String) -> Tool? {
        let k = urlKey.lowercased()
        if let exact = allCases.first(where: { $0.rawValue == k || $0.name.lowercased() == k }) { return exact }
        switch k {
        case "history", "paste": return .clipboard
        case "dictate", "voice", "speech": return .dictation
        case "screenshot", "screen": return .capture
        case "app", "launcher", "launch": return .apps
        case "find", "files", "spotlight": return .search
        case "calc", "calculator", "math", "console": return .rconsole
        case "sound", "output", "input", "devices": return .audio
        case "claude", "ask", "talk": return .chat
        case "issue", "issues", "gh": return .github
        default: return nil
        }
    }

    static func matching(key: Character) -> Tool? {
        let k = Character(key.lowercased())
        return allCases.first { $0.letter == k || $0.aliases.contains(k) }
    }

    /// Open the tool. Callers must have already hidden the chooser so that
    /// `NSWorkspace.frontmostApplication` still points at the user's app —
    /// every panel's show() reads it to know where to paste back.
    @MainActor
    func open() {
        switch self {
        case .clipboard: HistoryWindow.shared.show()
        case .emoji: EmojiWindow.shared.show()
        case .dictation: DictationWindow.shared.toggle()
        case .capture: ScreenCaptureWindow.shared.begin()
        case .apps: LauncherWindow.shared.show()
        case .search: SpotlightWindow.shared.show()
        case .rconsole: RConsoleWindow.shared.show()
        case .audio: AudioWindow.shared.show()
        case .chat: ChatWindow.shared.show()
        case .github: GitHubWindow.shared.show()
        }
    }

    /// Show if hidden, dismiss if visible — what a hotkey or URL wants.
    @MainActor
    func toggle() {
        switch self {
        case .clipboard: HistoryWindow.shared.toggle()
        case .emoji: EmojiWindow.shared.toggle()
        case .dictation: DictationWindow.shared.toggle()
        case .capture: ScreenCaptureWindow.shared.begin()
        case .apps: LauncherWindow.shared.toggle()
        case .search: SpotlightWindow.shared.toggle()
        case .rconsole: RConsoleWindow.shared.toggle()
        case .audio: AudioWindow.shared.toggle()
        case .chat: ChatWindow.shared.toggle()
        case .github: GitHubWindow.shared.toggle()
        }
    }
}
