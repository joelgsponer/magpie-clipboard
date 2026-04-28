import AppKit
import SwiftUI

struct ItemRow: View {
    let item: ClipboardItem
    let quickPasteIndex: Int?
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                if let n = quickPasteIndex {
                    Text("⌘\(n)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .image:
            if let data = HistoryStore.shared.imageData(for: item),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        case .files:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryText: String {
        switch item.kind {
        case .text:
            return (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
        case .image:
            return "Image"
        case .files:
            let urls = resolveFileURLs()
            if let first = urls.first {
                return first.lastPathComponent
            }
            let count = item.fileBookmarksB64?.count ?? 0
            return count == 1 ? "1 file" : "\(count) files"
        }
    }

    private var subtitle: String {
        let date = item.createdAt.formatted(.relative(presentation: .named))
        switch item.kind {
        case .text:
            let text = item.text ?? ""
            let lineCount = text.split(whereSeparator: \.isNewline).count
            if lineCount > 1 {
                return "\(lineCount) lines · \(date)"
            }
            if let bid = item.sourceBundleID {
                return "\(bid) · \(date)"
            }
            return date
        case .image:
            if let data = HistoryStore.shared.imageData(for: item),
               let image = NSImage(data: data) {
                let w = Int(image.size.width.rounded())
                let h = Int(image.size.height.rounded())
                return "PNG · \(w)×\(h) · \(date)"
            }
            return "PNG · \(date)"
        case .files:
            let count = item.fileBookmarksB64?.count ?? 0
            if count > 1 {
                let urls = resolveFileURLs()
                if let first = urls.first {
                    return "\(count) files · \(first.lastPathComponent) · \(date)"
                }
                return "\(count) files · \(date)"
            }
            return date
        }
    }

    private func resolveFileURLs() -> [URL] {
        (item.fileBookmarks ?? []).compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }
}
