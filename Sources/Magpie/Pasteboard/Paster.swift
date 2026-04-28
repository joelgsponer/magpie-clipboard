import AppKit
import Foundation

@MainActor
final class Paster {
    static let shared = Paster()

    /// The app that was frontmost before the Magpie window appeared. Set by HistoryWindow.
    var previousApp: NSRunningApplication?

    private let pasteboard = NSPasteboard.general

    private init() {}

    /// Unified entry point: paste-by-pasteboard or type-by-keystroke depending on `mode`.
    /// Non-text items always fall back to paste, since "type" makes no sense for image/files.
    func fire(_ item: ClipboardItem, mode: PasteMode) {
        if mode == .type, item.kind == .text, let text = item.text {
            type(text)
        } else {
            paste(item)
        }
    }

    func paste(_ item: ClipboardItem) {
        write(item)
        PasteboardWatcher.shared.skipNextChangeCount = pasteboard.changeCount

        let target = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            target?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.postCommandV()
            }
        }
    }

    func type(_ text: String) {
        let target = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            target?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.postUnicodeString(text)
            }
        }
    }

    private func write(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = HistoryStore.shared.imageData(for: item),
               let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .files:
            if let bookmarks = item.fileBookmarks {
                let urls: [URL] = bookmarks.compactMap { data in
                    var stale = false
                    return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                }
                if !urls.isEmpty {
                    pasteboard.writeObjects(urls as [NSURL])
                }
            }
        }
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down?.post(tap: tap)
        up?.post(tap: tap)
    }

    /// Type a string by synthesizing keyDown/keyUp CGEvents with Unicode payloads.
    /// Bypasses the pasteboard entirely — works in fields that block paste.
    private static func postUnicodeString(_ text: String) {
        let utf16 = Array(text.utf16)
        let chunkSize = 20
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap

        var i = 0
        while i < utf16.count {
            let end = Swift.min(i + chunkSize, utf16.count)
            let chunk = Array(utf16[i..<end])

            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                chunk.withUnsafeBufferPointer { ptr in
                    down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
                }
                down.post(tap: tap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                chunk.withUnsafeBufferPointer { ptr in
                    up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
                }
                up.post(tap: tap)
            }

            i = end
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
