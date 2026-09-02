import Foundation
import CryptoKit
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [ClipboardItem] = []
    var historyCap: Int = 500

    private let fm = FileManager.default
    private let dir: URL
    private let jsonURL: URL
    private let blobsDir: URL
    private var saveDebounce: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.dir = appSupport.appendingPathComponent("Magpie", isDirectory: true)
        self.jsonURL = dir.appendingPathComponent("history.json")
        self.blobsDir = dir.appendingPathComponent("blobs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public API

    func ingest(
        kind: ClipboardKind,
        text: String? = nil,
        imageData: Data? = nil,
        fileBookmarks: [Data]? = nil,
        sourceBundleID: String? = nil,
        extractedText: String? = nil,
        imageContext: String? = nil
    ) {
        let hash = Self.hash(kind: kind, text: text, imageData: imageData, fileBookmarks: fileBookmarks)

        if let idx = items.firstIndex(where: { $0.contentHash == hash }) {
            items[idx].createdAt = Date()
            // Backfill rather than drop. extractedText/imageContext are
            // deliberately excluded from the hash — including them would
            // change every existing image row's hash and duplicate it — so a
            // re-analysed capture lands here, and without this the analysis we
            // just paid Claude for would be silently thrown away. Bonus: a
            // plain ⇧⌘4 screenshot already ingested by PasteboardWatcher gets
            // upgraded with text + context when a capture runs over it later.
            if let extractedText { items[idx].extractedText = extractedText }
            if let imageContext { items[idx].imageContext = imageContext }
            sortAndCap()
            scheduleSave()
            return
        }

        var imageBlob: String? = nil
        if let imageData {
            let name = "\(hash).png"
            let url = blobsDir.appendingPathComponent(name)
            try? imageData.write(to: url, options: .atomic)
            imageBlob = name
        }

        let bookmarksB64 = fileBookmarks?.map { $0.base64EncodedString() }

        let item = ClipboardItem(
            kind: kind,
            text: text,
            imageBlob: imageBlob,
            fileBookmarksB64: bookmarksB64,
            extractedText: extractedText,
            imageContext: imageContext,
            sourceBundleID: sourceBundleID,
            contentHash: hash
        )
        items.append(item)
        sortAndCap()
        scheduleSave()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        sortAndCap()
        scheduleSave()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        if let blob = item.imageBlob {
            try? fm.removeItem(at: blobsDir.appendingPathComponent(blob))
        }
        scheduleSave()
    }

    func clearAllUnpinned() {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        for item in removed {
            if let blob = item.imageBlob {
                try? fm.removeItem(at: blobsDir.appendingPathComponent(blob))
            }
        }
        scheduleSave()
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard let blob = item.imageBlob else { return nil }
        return try? Data(contentsOf: blobsDir.appendingPathComponent(blob))
    }

    // MARK: - Persistence

    private func load() {
        guard fm.fileExists(atPath: jsonURL.path) else { return }
        do {
            let data = try Data(contentsOf: jsonURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.items = try decoder.decode([ClipboardItem].self, from: data)
            sortAndCap()
        } catch {
            NSLog("Magpie: failed to load history: \(error)")
        }
    }

    private func scheduleSave() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            NSLog("Magpie: failed to save history: \(error)")
        }
    }

    private func sortAndCap() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
        // Evict oldest non-pinned beyond cap.
        var unpinnedSeen = 0
        var keep: [ClipboardItem] = []
        var dropped: [ClipboardItem] = []
        for item in items {
            if item.pinned {
                keep.append(item)
            } else {
                if unpinnedSeen < historyCap {
                    keep.append(item)
                    unpinnedSeen += 1
                } else {
                    dropped.append(item)
                }
            }
        }
        items = keep
        for item in dropped {
            if let blob = item.imageBlob {
                try? fm.removeItem(at: blobsDir.appendingPathComponent(blob))
            }
        }
    }

    // MARK: - Hashing

    private static func hash(
        kind: ClipboardKind,
        text: String?,
        imageData: Data?,
        fileBookmarks: [Data]?
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        if let text { hasher.update(data: Data(text.utf8)) }
        if let imageData { hasher.update(data: imageData) }
        if let fileBookmarks {
            for b in fileBookmarks { hasher.update(data: b) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
