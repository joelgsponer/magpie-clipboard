import AppKit
import Foundation

@MainActor
final class PasteboardWatcher {
    static let shared = PasteboardWatcher()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Set by Paster before it writes back, so we don't re-ingest our own paste.
    var skipNextChangeCount: Int?

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        defer { lastChangeCount = current }

        if let skip = skipNextChangeCount, skip == current {
            skipNextChangeCount = nil
            return
        }

        ingestCurrent()
    }

    private func ingestCurrent() {
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let bookmarks = urls.compactMap { url -> Data? in
                try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            if !bookmarks.isEmpty {
                HistoryStore.shared.ingest(
                    kind: .files,
                    fileBookmarks: bookmarks,
                    sourceBundleID: sourceBundleID
                )
                return
            }
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            HistoryStore.shared.ingest(
                kind: .image,
                imageData: png,
                sourceBundleID: sourceBundleID
            )
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            HistoryStore.shared.ingest(
                kind: .text,
                text: text,
                sourceBundleID: sourceBundleID
            )
            return
        }
    }
}
