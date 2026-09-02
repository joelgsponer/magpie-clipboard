import Foundation

enum ClipboardKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ClipboardKind
    var text: String?
    /// Filename of the blob in the blobs/ directory (PNG). Nil for non-image kinds.
    var imageBlob: String?
    /// Bookmark data, base64-encoded for JSON.
    var fileBookmarksB64: [String]?
    /// Verbatim text read out of a captured image by the screen-capture
    /// analyser. Kept separate from `text`, which is load-bearing for .text
    /// items throughout Paster, ItemRow and the dedup hash.
    var extractedText: String?
    /// One-paragraph description of a captured image — what it is, where it
    /// came from, what it's about — for recognising it later in history.
    var imageContext: String?
    var createdAt: Date
    var pinned: Bool
    var sourceBundleID: String?
    var contentHash: String

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        text: String? = nil,
        imageBlob: String? = nil,
        fileBookmarksB64: [String]? = nil,
        extractedText: String? = nil,
        imageContext: String? = nil,
        createdAt: Date = Date(),
        pinned: Bool = false,
        sourceBundleID: String? = nil,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageBlob = imageBlob
        self.fileBookmarksB64 = fileBookmarksB64
        self.extractedText = extractedText
        self.imageContext = imageContext
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
    }

    var fileBookmarks: [Data]? {
        fileBookmarksB64?.compactMap { Data(base64Encoded: $0) }
    }
}
