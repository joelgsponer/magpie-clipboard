import AppKit
import SwiftUI

struct PreviewPane: View {
    let item: ClipboardItem?

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            textPreview(item.text ?? "")
        case .image:
            imagePreview(for: item)
        case .files:
            filesPreview(for: item)
        }
    }

    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private func imagePreview(for item: ClipboardItem) -> some View {
        Group {
            if let data = HistoryStore.shared.imageData(for: item),
               let nsImage = NSImage(data: data) {
                if hasAnalysis(item) {
                    // Vertical-only scrolling here: text needs a bounded width
                    // to wrap against, which a horizontal scroll axis removes.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                            if let context = item.imageContext, !context.isEmpty {
                                analysisSection("CONTEXT") {
                                    Text(context)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let extracted = item.extractedText, !extracted.isEmpty {
                                analysisSection("TEXT") {
                                    Text(extracted)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private func hasAnalysis(_ item: ClipboardItem) -> Bool {
        item.imageContext?.isEmpty == false || item.extractedText?.isEmpty == false
    }

    private func analysisSection<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            content()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filesPreview(for item: ClipboardItem) -> some View {
        let urls: [URL] = (item.fileBookmarks ?? []).compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select an item")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
