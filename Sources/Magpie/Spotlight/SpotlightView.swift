import SwiftUI

struct SpotlightView: View {
    @EnvironmentObject var state: SpotlightState
    @ObservedObject var search: SpotlightSearch = .shared

    var onOpen: (SpotlightResult) -> Void
    var onReveal: (SpotlightResult) -> Void
    var onCopyPath: (SpotlightResult) -> Void
    var onClose: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            list
            Divider().opacity(0.4)
            footer
            keyboardShortcuts
        }
        .frame(width: 640, height: 460)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { searchFocused = true }
        .onChange(of: state.activationToken) { _, _ in searchFocused = true }
        .onChange(of: state.query) { _, q in search.search(q) }
        .onChange(of: search.results.map(\.id)) { _, _ in ensureSelection() }
        .onExitCommand { onClose() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search files, folders, and content…", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit { openSelected() }
            if search.searching {
                ProgressView().controlSize(.small)
            } else if !search.results.isEmpty {
                Text("\(search.results.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var list: some View {
        if search.results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: state.query.isEmpty ? "sparkle.magnifyingglass" : "doc.questionmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(state.query.trimmingCharacters(in: .whitespaces).count < 2
                     ? "Type to search your Mac"
                     : (search.searching ? "Searching…" : "No results"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: $state.selectedID) {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { i, r in
                        row(r, quickIndex: i < 9 ? i + 1 : nil)
                            .tag(r.id)
                            .id(r.id)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowSeparator(.hidden)
                            .onTapGesture(count: 2) { onOpen(r) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: state.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func row(_ r: SpotlightResult, quickIndex: Int?) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: search.icon(for: r))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !r.kind.isEmpty {
                        Text(r.kind)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(abbreviate(r.url.deletingLastPathComponent().path))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let quickIndex {
                Text("⌘\(quickIndex)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HintGroup(keys: ["↵"], description: "open")
            HintGroup(keys: ["⌘", "↵"], description: "reveal")
            HintGroup(keys: ["⌘", "C"], description: "copy path")
            HintGroup(keys: ["⌘", "1–9"], description: "quick")
            HintGroup(keys: ["esc"], description: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: openSelected).keyboardShortcut(.return, modifiers: [])
            Button("", action: { if let r = selected { onReveal(r) } }).keyboardShortcut(.return, modifiers: .command)
            Button("", action: { if let r = selected { onCopyPath(r) } }).keyboardShortcut("c", modifiers: .command)
            Button("", action: { move(1) }).keyboardShortcut(.downArrow, modifiers: [])
            Button("", action: { move(-1) }).keyboardShortcut(.upArrow, modifiers: [])
            ForEach(1...9, id: \.self) { n in
                Button("", action: { pick(n - 1) })
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var selected: SpotlightResult? {
        search.results.first { $0.id == state.selectedID } ?? search.results.first
    }

    private func ensureSelection() {
        if let id = state.selectedID, search.results.contains(where: { $0.id == id }) { return }
        state.selectedID = search.results.first?.id
    }

    private func openSelected() {
        if let r = selected { onOpen(r) }
    }

    private func pick(_ i: Int) {
        guard search.results.indices.contains(i) else { return }
        onOpen(search.results[i])
    }

    private func move(_ offset: Int) {
        let rs = search.results
        guard !rs.isEmpty else { return }
        let current = rs.firstIndex { $0.id == state.selectedID } ?? -1
        let next = current < 0 ? (offset > 0 ? 0 : rs.count - 1) : max(0, min(rs.count - 1, current + offset))
        state.selectedID = rs[next].id
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
