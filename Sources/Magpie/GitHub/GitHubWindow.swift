import AppKit
import SwiftUI

@MainActor
final class GitHubState: ObservableObject {
    enum Step: Equatable {
        case pickRepo
        case compose
        case done(URL)
    }

    @Published var step: Step = .pickRepo
    @Published var query: String = ""
    @Published var selectedRepoID: String?
    @Published var repo: GitHubRepo?
    @Published var title: String = ""
    @Published var body: String = ""
    @Published var submitting = false
    @Published var error: String?
    @Published var activationToken: Int = 0
}

@MainActor
final class GitHubWindow {
    static let shared = GitHubWindow()

    private var panel: NSPanel?
    private let state = GitHubState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    /// A prefilled repo skips the picker; title/body land in the form.
    /// An unfinished draft survives an esc — only a completed issue resets.
    func show(repo: String? = nil, title: String? = nil, body: String? = nil) {
        previousApp = NSWorkspace.shared.frontmostApplication
        GitHubRepos.shared.refreshIfStale()

        let panel = panel ?? makePanel()
        self.panel = panel

        if case .done = state.step { reset() }
        if let repo, !repo.isEmpty {
            state.repo = GitHubRepos.shared.repos.first { $0.nameWithOwner.lowercased() == repo.lowercased() }
                ?? GitHubRepo(nameWithOwner: repo, description: "", isPrivate: false, pushedAt: nil)
            state.step = .compose
        }
        if let title { state.title = title }
        if let body { state.body = body }
        state.error = nil

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        state.activationToken += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func dismiss() {
        hide()
        if let target = previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private func reset() {
        state.step = .pickRepo
        state.query = ""
        state.title = ""
        state.body = ""
        state.error = nil
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel.make(width: 640, height: 480, autosaveName: "MagpieGitHubPanel")
        let view = GitHubView(
            onCreated: { [weak self] issue in
                guard let self else { return }
                self.state.step = .done(issue.url)
                // The link is what you want next — in a chat, a commit message.
                Paster.shared.copyText(issue.url.absoluteString)
                HistoryStore.shared.ingest(kind: .text, text: issue.url.absoluteString, sourceBundleID: "local.magpie")
            },
            onOpen: { [weak self] url in
                self?.dismiss()
                NSWorkspace.shared.open(url)
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
