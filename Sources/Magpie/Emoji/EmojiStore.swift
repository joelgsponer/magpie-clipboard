import Foundation

/// Search + recents for the emoji picker.
@MainActor
final class EmojiStore: ObservableObject {
    static let shared = EmojiStore()

    /// Emoji chars, most recently used first. Persisted in UserDefaults.
    @Published private(set) var recents: [String] = []

    private let recentsKey = "emojiRecents"
    private let recentsCap = 30

    private init() {
        recents = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    func record(_ char: String) {
        recents.removeAll { $0 == char }
        recents.insert(char, at: 0)
        if recents.count > recentsCap { recents = Array(recents.prefix(recentsCap)) }
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    var recentEntries: [EmojiEntry] {
        let byChar = Dictionary(grouping: EmojiData.entries, by: \.char).compactMapValues(\.first)
        return recents.compactMap { byChar[$0] }
    }

    /// Fuzzy search over CLDR names. Empty query returns everything in category order.
    func search(_ query: String) -> [EmojiEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return EmojiData.entries }

        var scored: [(entry: EmojiEntry, score: Int)] = []
        scored.reserveCapacity(64)
        for entry in EmojiData.entries {
            if let s = FuzzyMatcher.score(query: q, in: entry.name) {
                scored.append((entry, s))
            }
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.entry.name < rhs.entry.name
        }
        return scored.map(\.entry)
    }
}
