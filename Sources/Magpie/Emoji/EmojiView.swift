import SwiftUI

struct EmojiView: View {
    @ObservedObject var store: EmojiStore = .shared

    /// pick(emoji, copyOnly, typeInsteadOfPaste)
    var onPick: (EmojiEntry, Bool, Bool) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var activator: EmojiActivator
    @State private var searchText: String = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    private let columns = 10
    private let cellSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider().opacity(0.4)

            grid

            Divider().opacity(0.4)

            footer

            keyboardShortcuts
        }
        .frame(width: 460, height: 480)
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
        .onChange(of: activator.token) { _, _ in
            searchText = ""
            searchFocused = true
            ensureValidSelection()
        }
        .onChange(of: searchText) { _, _ in ensureValidSelection() }
        .onExitCommand { onClose() }
    }

    // MARK: - Data

    /// Flat, in-display-order list used for arrow-key navigation.
    private var visible: [EmojiEntry] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return store.recentEntries + EmojiData.entries
        }
        return store.search(searchText)
    }

    private var sections: [(title: String, entries: [EmojiEntry])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let results = store.search(query)
            return results.isEmpty ? [] : [("Results", results)]
        }
        var result: [(String, [EmojiEntry])] = []
        let recents = store.recentEntries
        if !recents.isEmpty { result.append(("Frequently Used", recents)) }
        for category in EmojiData.categories {
            result.append((category, EmojiData.entries.filter { $0.category == category }))
        }
        return result
    }

    // MARK: - Sections

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search emoji…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit { pick(copyOnly: false, type: false) }

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var grid: some View {
        if visible.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 2), count: columns),
                        spacing: 2,
                        pinnedViews: [.sectionHeaders]
                    ) {
                        ForEach(sections, id: \.title) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    cell(for: entry)
                                }
                            } header: {
                                HStack {
                                    Text(section.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.regularMaterial)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
                .onChange(of: activator.token) { _, _ in
                    guard let id = selectedID ?? visible.first?.id else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    private func cell(for entry: EmojiEntry) -> some View {
        Text(entry.char)
            .font(.system(size: 24))
            .frame(width: cellSize, height: cellSize)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selectedID == entry.id ? Color.accentColor.opacity(0.25) : .clear)
            )
            .help(entry.name)
            .id(entry.id)
            .onTapGesture {
                selectedID = entry.id
                pick(entry, copyOnly: false, type: false)
            }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            EmojiHint(keys: ["↵"], description: "paste")
            EmojiHint(keys: ["⇧", "↵"], description: "type")
            EmojiHint(keys: ["⌘", "↵"], description: "copy")
            EmojiHint(keys: ["←→↑↓"], description: "move")
            EmojiHint(keys: ["esc"], description: "close")
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: { pick(copyOnly: false, type: false) })
                .keyboardShortcut(.return, modifiers: [])
            Button("", action: { pick(copyOnly: false, type: true) })
                .keyboardShortcut(.return, modifiers: .shift)
            Button("", action: { pick(copyOnly: true, type: false) })
                .keyboardShortcut(.return, modifiers: .command)
            Button("", action: { move(by: -1) })
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: { move(by: 1) })
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("", action: { move(by: -columns) })
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("", action: { move(by: columns) })
                .keyboardShortcut(.downArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Selection / actions

    private func ensureValidSelection() {
        if let id = selectedID, visible.contains(where: { $0.id == id }) { return }
        selectedID = visible.first?.id
    }

    private func move(by offset: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? -1
        let newIndex: Int
        if current < 0 {
            newIndex = offset > 0 ? 0 : visible.count - 1
        } else {
            newIndex = max(0, min(visible.count - 1, current + offset))
        }
        selectedID = visible[newIndex].id
    }

    private func pick(copyOnly: Bool, type: Bool) {
        let entry = visible.first { $0.id == selectedID } ?? visible.first
        if let entry { pick(entry, copyOnly: copyOnly, type: type) }
    }

    private func pick(_ entry: EmojiEntry, copyOnly: Bool, type: Bool) {
        onPick(entry, copyOnly, type)
    }
}

// MARK: - Footer chip

private struct EmojiHint: View {
    let keys: [String]
    let description: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
