import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: HistoryStore = .shared

    var onPick: (ClipboardItem) -> Void
    var onClose: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider().opacity(0.4)

            HStack(spacing: 0) {
                listColumn
                    .frame(width: 320)
                Divider().opacity(0.4)
                PreviewPane(item: selectedItem)
            }

            Divider().opacity(0.4)

            footer

            keyboardShortcuts
        }
        .frame(width: 760, height: 540)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            searchFocused = true
            ensureValidSelection()
        }
        .onChange(of: appState.activationToken) { _, _ in
            searchFocused = true
            ensureValidSelection()
        }
        .onChange(of: filtered.map(\.id)) { _, _ in
            ensureValidSelection()
        }
        .onExitCommand { onClose() }
    }

    // MARK: - Sections

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search clipboard…", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular, design: .default))
                .focused($searchFocused)
                .onSubmit { pickSelectedOrFirst() }

            if !appState.searchText.isEmpty {
                Button { appState.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("\(filtered.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var listColumn: some View {
        if filtered.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: appState.searchText.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(appState.searchText.isEmpty ? "Clipboard is empty" : "No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: $appState.selectedItemID) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            quickPasteIndex: index < 9 ? index + 1 : nil,
                            onTogglePin: { store.togglePin(item) },
                            onDelete: { store.delete(item) }
                        )
                        .tag(item.id)
                        .id(item.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .onTapGesture(count: 2) { onPick(item) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: appState.selectedItemID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
                .onChange(of: appState.activationToken) { _, _ in
                    guard let id = appState.selectedItemID ?? filtered.first?.id else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HintGroup(keys: [keyLabel], description: appState.pasteMode == .type ? "type" : "paste")
            HintGroup(keys: ["⌘", "1–9"], description: "quick")
            HintGroup(keys: ["⌘", "P"], description: "pin")
            HintGroup(keys: ["⌫"], description: "delete")
            HintGroup(keys: ["esc"], description: "close")

            Spacer(minLength: 8)

            Picker("", selection: $appState.pasteMode) {
                ForEach(PasteMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyLabel: String { "↵" }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: pickSelectedOrFirst)
                .keyboardShortcut(.return, modifiers: [])
            Button("", action: { moveSelection(by: 1) })
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("", action: { moveSelection(by: -1) })
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("", action: togglePinSelected)
                .keyboardShortcut("p", modifiers: .command)
            Button("", action: deleteSelected)
                .keyboardShortcut(.delete, modifiers: [])
            ForEach(1...9, id: \.self) { n in
                Button("", action: { pickIndex(n - 1) })
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Filtering

    private var filtered: [ClipboardItem] {
        let query = appState.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.items }

        struct Scored {
            let item: ClipboardItem
            let score: Int
        }

        let scored: [Scored] = store.items.compactMap { item in
            guard let s = FuzzyMatcher.score(query: query, in: searchableText(for: item)) else { return nil }
            return Scored(item: item, score: s)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.item.pinned != rhs.item.pinned { return lhs.item.pinned && !rhs.item.pinned }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.createdAt > rhs.item.createdAt
            }
            .map(\.item)
    }

    private func searchableText(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let s = item.text ?? ""
            if s.count > 200 { return String(s.prefix(200)) }
            return s
        case .image:
            // Cap the extracted text the same way .text does: FuzzyMatcher
            // scores every item on every keystroke, and a screenshot of dense
            // output can carry kilobytes.
            var s = "image"
            if let context = item.imageContext { s += " " + context }
            if let extracted = item.extractedText { s += " " + extracted.prefix(200) }
            return s
        case .files:
            let firstName = item.fileBookmarks?.first
                .flatMap { data -> URL? in
                    var stale = false
                    return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                }?
                .lastPathComponent ?? ""
            return "file \(firstName)"
        }
    }

    // MARK: - Selection / actions

    private var selectedItem: ClipboardItem? {
        guard let id = appState.selectedItemID else { return nil }
        return filtered.first(where: { $0.id == id })
    }

    private func ensureValidSelection() {
        if let id = appState.selectedItemID, filtered.contains(where: { $0.id == id }) {
            return
        }
        appState.selectedItemID = filtered.first?.id
    }

    private func pickSelectedOrFirst() {
        if let item = selectedItem {
            onPick(item)
        } else if let first = filtered.first {
            onPick(first)
        }
    }

    private func pickIndex(_ index: Int) {
        guard filtered.indices.contains(index) else { return }
        onPick(filtered[index])
    }

    private func moveSelection(by offset: Int) {
        guard !filtered.isEmpty else { return }
        let currentIndex = filtered.firstIndex { $0.id == appState.selectedItemID } ?? -1
        let newIndex: Int
        if currentIndex < 0 {
            newIndex = offset > 0 ? 0 : filtered.count - 1
        } else {
            newIndex = max(0, min(filtered.count - 1, currentIndex + offset))
        }
        appState.selectedItemID = filtered[newIndex].id
    }

    private func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(item)
    }

    private func deleteSelected() {
        guard let item = selectedItem,
              let index = filtered.firstIndex(where: { $0.id == item.id }) else { return }
        store.delete(item)
        let after = filtered
        if after.indices.contains(index) {
            appState.selectedItemID = after[index].id
        } else if !after.isEmpty {
            appState.selectedItemID = after.last?.id
        } else {
            appState.selectedItemID = nil
        }
    }
}

// MARK: - Footer chip

/// Shared with ScreenCaptureView's footer.
struct HintGroup: View {
    let keys: [String]
    let description: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
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
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
