import SwiftUI

struct LauncherView: View {
    @EnvironmentObject var state: LauncherState
    @ObservedObject var index: AppIndex = .shared

    var onLaunch: (LaunchableApp) -> Void
    var onReveal: (LaunchableApp) -> Void
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
        .frame(width: 600, height: 440)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { searchFocused = true; ensureSelection() }
        .onChange(of: state.activationToken) { _, _ in searchFocused = true; ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onExitCommand { onClose() }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Launch an app…", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit { launchSelected() }
            if index.scanning {
                ProgressView().controlSize(.small)
            } else {
                Text("\(filtered.count)")
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
        if filtered.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(index.apps.isEmpty ? "Scanning applications…" : "No matching app")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(selection: $state.selectedID) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, app in
                        row(app, quickIndex: i < 9 ? i + 1 : nil)
                            .tag(app.id)
                            .id(app.id)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .listRowSeparator(.hidden)
                            .onTapGesture(count: 2) { onLaunch(app) }
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

    private func row(_ app: LaunchableApp, quickIndex: Int?) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: index.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if index.isRunning(app) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                }
                Text(abbreviate(app.url.deletingLastPathComponent().path))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
            HintGroup(keys: ["⌘", "↵"], description: "reveal in Finder")
            HintGroup(keys: ["⌘", "1–9"], description: "quick")
            HintGroup(keys: ["esc"], description: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: launchSelected).keyboardShortcut(.return, modifiers: [])
            Button("", action: revealSelected).keyboardShortcut(.return, modifiers: .command)
            Button("", action: { move(1) }).keyboardShortcut(.downArrow, modifiers: [])
            Button("", action: { move(-1) }).keyboardShortcut(.upArrow, modifiers: [])
            Button("", action: { AppIndex.shared.refreshIfStale(force: true) }).keyboardShortcut("r", modifiers: .command)
            ForEach(1...9, id: \.self) { n in
                Button("", action: { pick(n - 1) })
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Data

    private var filtered: [LaunchableApp] {
        let query = state.query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return index.apps.sorted { a, b in
                let ca = index.launchCount(for: a), cb = index.launchCount(for: b)
                if ca != cb { return ca > cb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        return index.apps
            .compactMap { app -> (LaunchableApp, Int)? in
                guard let s = FuzzyMatcher.score(query: query, in: app.name) else { return nil }
                return (app, s + min(index.launchCount(for: app), 20) * 3)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var selected: LaunchableApp? {
        filtered.first { $0.id == state.selectedID }
    }

    private func ensureSelection() {
        if let id = state.selectedID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedID = filtered.first?.id
    }

    private func launchSelected() {
        if let app = selected ?? filtered.first { onLaunch(app) }
    }

    private func revealSelected() {
        if let app = selected ?? filtered.first { onReveal(app) }
    }

    private func pick(_ i: Int) {
        guard filtered.indices.contains(i) else { return }
        onLaunch(filtered[i])
    }

    private func move(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let current = filtered.firstIndex { $0.id == state.selectedID } ?? -1
        let next = current < 0 ? (offset > 0 ? 0 : filtered.count - 1) : max(0, min(filtered.count - 1, current + offset))
        state.selectedID = filtered[next].id
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
