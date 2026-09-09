import SwiftUI

struct GitHubView: View {
    @EnvironmentObject var state: GitHubState
    @ObservedObject var repos: GitHubRepos = .shared

    var onCreated: (GitHubRepos.CreatedIssue) -> Void
    var onOpen: (URL) -> Void
    var onClose: () -> Void

    private enum Field: Hashable { case search, title, body }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            switch state.step {
            case .pickRepo: picker
            case .compose: compose
            case .done(let url): done(url)
            }
            keyboardShortcuts
        }
        .frame(width: 640, height: 480)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { focusForStep(); ensureSelection() }
        .onChange(of: state.activationToken) { _, _ in focusForStep(); ensureSelection() }
        .onChange(of: state.step) { _, _ in focusForStep() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onExitCommand { onClose() }
    }

    private func focusForStep() {
        switch state.step {
        case .pickRepo: focus = .search
        case .compose: focus = state.title.isEmpty ? .title : .body
        case .done: focus = nil
        }
    }

    // MARK: - Step 1: repository

    private var picker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("New issue in…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focus, equals: .search)
                    .onSubmit { chooseSelected() }
                if repos.loading {
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

            Divider().opacity(0.4)

            if let error = repos.error, repos.repos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { repos.refreshIfStale(force: true) }.controlSize(.small)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: repos.repos.isEmpty ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(repos.repos.isEmpty ? "Loading repositories…" : "No matching repository")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $state.selectedRepoID) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, repo in
                            repoRow(repo, quickIndex: i < 9 ? i + 1 : nil)
                                .tag(repo.id)
                                .id(repo.id)
                                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                                .listRowSeparator(.hidden)
                                .onTapGesture(count: 2) { choose(repo) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: state.selectedRepoID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }

            Divider().opacity(0.4)
            HStack(spacing: 14) {
                HintGroup(keys: ["↵"], description: "choose")
                HintGroup(keys: ["⌘", "1–9"], description: "quick")
                HintGroup(keys: ["⌘", "R"], description: "refresh")
                HintGroup(keys: ["esc"], description: "close")
                Spacer()
                if let error = repos.error {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func repoRow(_ repo: GitHubRepo, quickIndex: Int?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(repo.owner + "/").foregroundStyle(.secondary)
                    Text(repo.name).fontWeight(.medium)
                }
                .font(.system(size: 13))
                .lineLimit(1)
                HStack(spacing: 6) {
                    if let pushed = repo.pushedAt {
                        Text(pushed, format: .relative(presentation: .named))
                            .foregroundStyle(.tertiary)
                    }
                    if !repo.description.isEmpty {
                        Text(repo.description).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                .font(.system(size: 10))
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

    // MARK: - Step 2: compose

    private var compose: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("New issue")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    state.step = .pickRepo
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: state.repo?.isPrivate == true ? "lock.fill" : "book.closed.fill")
                        Text(state.repo?.nameWithOwner ?? "choose repository")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.small)
                .help("Change repository (⌘⇧R)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $state.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .medium))
                    .focused($focus, equals: .title)
                    .onSubmit { focus = .body }

                Divider().opacity(0.3)

                ZStack(alignment: .topLeading) {
                    if state.body.isEmpty {
                        Text("Describe it (markdown works)…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $state.body)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .focused($focus, equals: .body)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)

            if let error = state.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider().opacity(0.4)

            HStack(spacing: 14) {
                HintGroup(keys: ["⌘", "↵"], description: "create issue")
                HintGroup(keys: ["⌘", "⇧", "R"], description: "repository")
                HintGroup(keys: ["esc"], description: "close")
                Spacer()
                if state.submitting {
                    ProgressView().controlSize(.small)
                    Text("Creating…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Button("Create issue") { submit() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Step 3: done

    private func done(_ url: URL) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Issue #\(url.lastPathComponent) created")
                .font(.system(size: 17, weight: .semibold))
            Text(state.repo?.nameWithOwner ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Text("Link copied to the clipboard.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Divider().opacity(0.4)
            HStack(spacing: 14) {
                HintGroup(keys: ["↵"], description: "open in browser")
                HintGroup(keys: ["⌘", "N"], description: "another issue")
                HintGroup(keys: ["esc"], description: "close")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Keys

    private var keyboardShortcuts: some View {
        VStack {
            switch state.step {
            case .pickRepo:
                Button("", action: { move(1) }).keyboardShortcut(.downArrow, modifiers: [])
                Button("", action: { move(-1) }).keyboardShortcut(.upArrow, modifiers: [])
                Button("", action: { repos.refreshIfStale(force: true) }).keyboardShortcut("r", modifiers: .command)
                ForEach(1...9, id: \.self) { n in
                    Button("", action: { pick(n - 1) })
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            case .compose:
                Button("", action: submit).keyboardShortcut(.return, modifiers: .command)
                Button("", action: { state.step = .pickRepo }).keyboardShortcut("r", modifiers: [.command, .shift])
            case .done(let url):
                Button("", action: { onOpen(url) }).keyboardShortcut(.return, modifiers: [])
                Button("", action: { startAnother() }).keyboardShortcut("n", modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Data and actions

    private var filtered: [GitHubRepo] {
        let query = state.query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return repos.repos.sorted { a, b in
                let ua = repos.useCount(a), ub = repos.useCount(b)
                if ua != ub { return ua > ub }
                return (a.pushedAt ?? .distantPast) > (b.pushedAt ?? .distantPast)
            }
        }
        return repos.repos
            .compactMap { repo -> (GitHubRepo, Int)? in
                let inName = FuzzyMatcher.score(query: query, in: repo.nameWithOwner)
                let inShort = FuzzyMatcher.score(query: query, in: repo.name).map { $0 + 20 }
                guard let best = [inName, inShort].compactMap({ $0 }).max() else { return nil }
                return (repo, best + min(repos.useCount(repo), 10) * 5)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var selected: GitHubRepo? {
        filtered.first { $0.id == state.selectedRepoID } ?? filtered.first
    }

    private func ensureSelection() {
        if let id = state.selectedRepoID, filtered.contains(where: { $0.id == id }) { return }
        state.selectedRepoID = filtered.first?.id
    }

    private func move(_ offset: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == state.selectedRepoID } ?? -1
        let next = current < 0 ? (offset > 0 ? 0 : list.count - 1) : max(0, min(list.count - 1, current + offset))
        state.selectedRepoID = list[next].id
    }

    private func chooseSelected() {
        if let repo = selected { choose(repo) }
    }

    private func pick(_ i: Int) {
        guard filtered.indices.contains(i) else { return }
        choose(filtered[i])
    }

    private func choose(_ repo: GitHubRepo) {
        state.repo = repo
        state.error = nil
        state.step = .compose
    }

    private var canSubmit: Bool {
        state.repo != nil && !state.title.trimmingCharacters(in: .whitespaces).isEmpty && !state.submitting
    }

    private func submit() {
        guard canSubmit, let repo = state.repo else { return }
        state.submitting = true
        state.error = nil
        repos.recordUse(repo)
        repos.createIssue(in: repo, title: state.title.trimmingCharacters(in: .whitespaces), body: state.body) { result in
            state.submitting = false
            switch result {
            case .success(let issue):
                state.title = ""
                state.body = ""
                onCreated(issue)
            case .failure(let error):
                state.error = error.localizedDescription
            }
        }
    }

    private func startAnother() {
        state.step = .compose
        state.title = ""
        state.body = ""
        state.error = nil
    }
}
