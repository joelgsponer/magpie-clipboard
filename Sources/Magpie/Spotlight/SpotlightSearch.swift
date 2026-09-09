import AppKit
import Foundation

struct SpotlightResult: Identifiable, Hashable {
    let url: URL
    let name: String
    let kind: String
    let lastUsed: Date?

    var id: String { url.path }
}

/// A thin NSMetadataQuery wrapper: one query per search, gathered once
/// (no live updates — the panel is transient), results snapshotted into
/// plain values so the view never touches NSMetadataItem.
@MainActor
final class SpotlightSearch: ObservableObject {
    static let shared = SpotlightSearch()

    @Published private(set) var results: [SpotlightResult] = []
    @Published private(set) var searching = false

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var debounce: DispatchWorkItem?
    private var iconCache: [String: NSImage] = [:]

    private static let maxResults = 60

    private init() {}

    func search(_ text: String) {
        debounce?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // One character against the whole index gathers tens of thousands
        // of rows before the first result can show; wait for a second one.
        guard trimmed.count >= 2 else {
            stop()
            results = []
            searching = false
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.run(trimmed) }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func clear() {
        debounce?.cancel()
        stop()
        results = []
        searching = false
    }

    func icon(for result: SpotlightResult) -> NSImage {
        if let cached = iconCache[result.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: result.url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[result.id] = icon
        return icon
    }

    // MARK: - Query

    private func run(_ text: String) {
        stop()
        searching = true

        let q = NSMetadataQuery()
        // Not the "Indexed" variant: NSMetadataQueryIndexedLocalComputerScope
        // gathers zero results on Sonoma+ for a non-sandboxed app, while
        // the plain scope returns the full index.
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.predicate = Self.predicate(for: text)
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        q.notificationBatchingInterval = 0.2

        let finished = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.gather(from: q, text: text) }
        }
        observers = [finished]
        query = q
        q.start()
    }

    private func stop() {
        query?.stop()
        query = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func gather(from q: NSMetadataQuery, text: String) {
        q.disableUpdates()
        defer { stop(); searching = false }

        let lowered = text.lowercased()
        var out: [SpotlightResult] = []
        let count = min(q.resultCount, 400)
        for i in 0..<count {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? (path as NSString).lastPathComponent
            let kind = (item.value(forAttribute: NSMetadataItemKindKey) as? String) ?? ""
            let used = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
                ?? item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            out.append(SpotlightResult(url: URL(fileURLWithPath: path), name: name, kind: kind, lastUsed: used))
        }

        // Name hits first (prefix, then substring), then everything else by
        // recency — content matches are only as good as their freshness.
        func rank(_ r: SpotlightResult) -> Int {
            let n = r.name.lowercased()
            if n.hasPrefix(lowered) { return 0 }
            if n.contains(lowered) { return 1 }
            return 2
        }
        out.sort { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast)
        }
        results = Array(out.prefix(Self.maxResults))
    }

    /// Raw Spotlight query syntax (not NSPredicate format strings): every word
    /// must appear either in the display name (anywhere) or — once the word
    /// is long enough to mean something — in the indexed text content (word
    /// prefix). `cd` = case- and diacritic-insensitive.
    nonisolated private static func predicate(for text: String) -> NSPredicate {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let clauses = words.map { word -> String in
            let escaped = word
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let name = "kMDItemDisplayName == \"*\(escaped)*\"cd"
            guard word.count >= 3 else { return "(\(name))" }
            return "(\(name) || kMDItemTextContent == \"\(escaped)*\"cd)"
        }
        let raw = clauses.joined(separator: " && ")
        return NSPredicate(fromMetadataQueryString: raw)
            ?? NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", text)
    }
}
