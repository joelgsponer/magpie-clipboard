import AppKit
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: ChatState
    @ObservedObject var chat: ChatManager = .shared

    var onClose: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            transcript
            Divider().opacity(0.4)
            inputBar
            Divider().opacity(0.4)
            footer
            keyboardShortcuts
        }
        .frame(minWidth: 520, minHeight: 400)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { inputFocused = true }
        .onChange(of: state.activationToken) { _, _ in inputFocused = true }
        .onExitCommand { onClose() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Claude")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 5) {
                Circle()
                    .fill(chat.sessionID == nil ? Color.secondary.opacity(0.4) : Color.green)
                    .frame(width: 6, height: 6)
                Text(chat.sessionID == nil ? "new session" : "session · \(chat.messages.filter { $0.role == .user }.count) turns")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Picker("", selection: $chat.modelID) {
                ForEach(ChatModel.all) { model in
                    Text(model.label).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()

            Button {
                ChatManager.ensureHome()
                NSWorkspace.shared.open(ChatManager.home)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Open ~/Magpie — the assistant's folder, with its CLAUDE.md and skills")

            Button {
                chat.newChat()
            } label: {
                Label("New", systemImage: "plus.bubble")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .disabled(chat.messages.isEmpty && chat.sessionID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if chat.messages.isEmpty {
            VStack(spacing: 10) {
                TVStaticView(active: false)
                    .frame(width: 140, height: 56)
                Text("Ask anything. System info, a quick fix, the weather.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if chat.cliPath == nil {
                    Text("Looking for the claude command…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(chat.messages) { message in
                            bubble(message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: chat.messages.last?.text) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.22)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !message.toolNotes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.toolNotes.enumerated()), id: \.offset) { _, tool in
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape.fill").font(.system(size: 9))
                                Text(tool).font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
                if message.text.isEmpty && message.isStreaming {
                    HStack(spacing: 10) {
                        TVStaticView(active: true)
                            .frame(width: 120, height: 46)
                        Text(message.toolNotes.isEmpty ? "thinking…" : "working…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if !message.text.isEmpty {
                    MarkdownView(markdown: message.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                if !message.isStreaming, !message.text.isEmpty {
                    HStack(spacing: 10) {
                        Button {
                            Paster.shared.copyText(message.text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        if let cost = message.costUSD {
                            Text(String(format: "$%.3f", cost))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Claude…  (⌥↵ for a new line)", text: $state.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { send() }
                .disabled(chat.isBusy)

            if chat.isBusy {
                Button { chat.cancel() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else {
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $chat.fullPermissions) {
                Label("Full permissions", systemImage: chat.fullPermissions ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Run claude with --dangerously-skip-permissions so it can execute commands and edit files without asking. ⌘P")

            Toggle(isOn: $chat.voiceOutput) {
                Label("Speak replies", systemImage: chat.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Read each reply aloud when it arrives. ⌘⇧S")

            if chat.isSpeaking {
                Button("Stop speaking") { chat.stopSpeaking() }
                    .controlSize(.mini)
            }

            Spacer()

            if chat.totalCostUSD > 0 {
                Text(String(format: "$%.3f", chat.totalCostUSD))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            HintGroup(keys: ["↵"], description: "send")
            HintGroup(keys: ["⌘", "N"], description: "new")
            HintGroup(keys: ["⌘", "."], description: "stop")
            HintGroup(keys: ["esc"], description: "close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: { chat.newChat() }).keyboardShortcut("n", modifiers: .command)
            Button("", action: { chat.cancel() }).keyboardShortcut(".", modifiers: .command)
            Button("", action: { chat.fullPermissions.toggle() }).keyboardShortcut("p", modifiers: .command)
            Button("", action: { chat.voiceOutput.toggle() }).keyboardShortcut("s", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func send() {
        let text = state.draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !chat.isBusy else { return }
        state.draft = ""
        chat.send(text)
    }
}

/// The "thinking" indicator: an old TV between channels. A grid of cells
/// re-rolled every frame, darker scan lines, and a slow brightness flicker.
struct TVStaticView: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 20 : 1.0 / 4)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                var rng = SplitMix64(seed: UInt64(t * (active ? 1000 : 4)))
                let cols = 40
                let rows = 14
                let cw = size.width / CGFloat(cols)
                let rh = size.height / CGFloat(rows)
                let flicker = active ? 0.75 + 0.25 * sin(t * 9.1) * sin(t * 2.3) : 0.35
                for r in 0..<rows {
                    let scan = r % 2 == 0 ? 1.0 : 0.72
                    for c in 0..<cols {
                        let v = Double(rng.next() % 1000) / 1000
                        let shade = (v * v) * flicker * scan
                        let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * rh, width: cw + 0.5, height: rh + 0.5)
                        context.fill(Path(rect), with: .color(Color(white: 0.15 + 0.85 * shade)))
                    }
                }
                // A rolling bar, the way a bad signal drifts.
                if active {
                    let y = CGFloat((t * 0.6).truncatingRemainder(dividingBy: 1)) * size.height
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rh * 1.5)), with: .color(Color.white.opacity(0.10)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Deterministic per-frame noise; SystemRandomNumberGenerator would be fine
/// but a seeded generator keeps a frame stable across re-renders in a tick.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
