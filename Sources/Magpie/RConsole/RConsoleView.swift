import AppKit
import SwiftUI

struct RConsoleView: View {
    @EnvironmentObject var state: RConsoleState
    @ObservedObject var session: RSession = .shared

    var onClose: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                console
                if session.latestPlot != nil {
                    Divider().opacity(0.4)
                    plotPane
                        .frame(minWidth: 280, idealWidth: 360, maxWidth: 480)
                }
            }
            Divider().opacity(0.4)
            inputBar
            Divider().opacity(0.4)
            footer
            keyboardShortcuts
        }
        .frame(minWidth: 600, minHeight: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { inputFocused = true }
        .onChange(of: state.activationToken) { _, _ in inputFocused = true }
        .onExitCommand { onClose() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "r.square.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.85))
            Text(session.versionString)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                session.clear()
            } label: {
                Label("Clear", systemImage: "eraser").font(.system(size: 11))
            }
            .controlSize(.small)
            Button {
                session.restart()
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise").font(.system(size: 11))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch session.status {
        case .ready: return session.isRunning ? .orange : .green
        case .starting: return .yellow
        case .stopped: return .secondary
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch session.status {
        case .ready: return session.isRunning ? "running…" : "ready"
        case .starting: return "starting…"
        case .stopped: return "stopped"
        case .failed(let m): return m
        }
    }

    // MARK: - Console

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A live R session. Type an expression and press ↵.")
                            Text("plot(), hist(), ggplot… render on the right. ⌘⇧P copies the plot, ⌘⇧C the last output.")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                    }
                    ForEach(session.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(">")
                                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.85))
                                Text(entry.code)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            if !entry.output.isEmpty {
                                Text(entry.output)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(entry.output.hasPrefix("Error") ? Color.orange : Color.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !entry.isDone {
                                ProgressView().controlSize(.mini)
                            }
                            if entry.plot != nil {
                                Label("plot", systemImage: "chart.xyaxis.line")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.entries.last?.output) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: session.entries.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    // MARK: - Plot

    @ViewBuilder
    private var plotPane: some View {
        if let plot = session.latestPlot {
            VStack(spacing: 8) {
                Image(nsImage: plot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                HStack(spacing: 8) {
                    Button {
                        session.copyLatestPlot()
                    } label: {
                        Label("Copy plot", systemImage: "doc.on.doc").font(.system(size: 11))
                    }
                    .controlSize(.small)
                    if let url = session.latestPlotURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Reveal PNG", systemImage: "folder").font(.system(size: 11))
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }
            .padding(12)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(">")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.85))
            TextField("x <- rnorm(100); hist(x)", text: $state.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(1...8)
                .focused($inputFocused)
                .autocorrectionDisabled()
                .onSubmit { submit() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HintGroup(keys: ["↵"], description: "run")
            HintGroup(keys: ["⌥", "↵"], description: "newline")
            HintGroup(keys: ["⌘", "↑↓"], description: "history")
            HintGroup(keys: ["⌘", "⇧", "C"], description: "copy output")
            HintGroup(keys: ["⌘", "⇧", "P"], description: "copy plot")
            HintGroup(keys: ["⌘", "K"], description: "clear")
            HintGroup(keys: ["⌘", "R"], description: "restart")
            HintGroup(keys: ["esc"], description: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: { historyStep(-1) }).keyboardShortcut(.upArrow, modifiers: .command)
            Button("", action: { historyStep(1) }).keyboardShortcut(.downArrow, modifiers: .command)
            Button("", action: { session.clear() }).keyboardShortcut("k", modifiers: .command)
            Button("", action: { session.restart() }).keyboardShortcut("r", modifiers: .command)
            Button("", action: { if let out = session.lastOutput { Paster.shared.copyText(out) } })
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("", action: { session.copyLatestPlot() }).keyboardShortcut("p", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func submit() {
        let code = state.input
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.input = ""
        state.historyIndex = nil
        session.run(code)
    }

    private func historyStep(_ delta: Int) {
        let h = session.history
        guard !h.isEmpty else { return }
        let current = state.historyIndex ?? h.count
        let next = max(0, min(h.count, current + delta))
        state.historyIndex = next == h.count ? nil : next
        state.input = next == h.count ? "" : h[next]
    }
}
