import SwiftUI

struct DictationView: View {
    @ObservedObject private var manager: DictationManager = .shared

    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            hint
            keyboardShortcuts
        }
        .padding(24)
        .frame(width: 480, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onExitCommand { onClose() }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle, .requestingAccess:
            ProgressView()
            Text("Waiting for microphone access…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .loadingModel:
            ProgressView()
            Text("Loading speech model… (first run only)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .recording:
            RecordingIndicator(startedAt: manager.recordingStartedAt)
            WaveformView(levelMeter: manager.levelMeter)

        case .transcribing:
            ProgressView()
            Text("Transcribing…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .done(let text):
            VStack(spacing: 10) {
                Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                TranscriptText(text, placeholder: "")
            }

        case .error(let message):
            VStack(spacing: 10) {
                Label("Dictation failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var hint: some View {
        switch manager.state {
        case .recording:
            Text("⌘⇧D to stop · esc to cancel")
        case .done, .error:
            Text("⌘⇧D or esc to close")
        default:
            Text("esc to cancel")
        }
    }

    /// Hidden button so Esc closes the panel even though nothing here takes
    /// text-field focus (no TextField to anchor onExitCommand to).
    private var keyboardShortcuts: some View {
        Button("", action: onClose)
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
    }
}

private struct RecordingIndicator: View {
    let startedAt: Date?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text("Recording…")
                .font(.system(size: 13, weight: .semibold))
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(elapsedString(from: startedAt, to: context.date))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Live audio-level bars, redrawn ~30fps by polling a LevelMeter snapshot —
/// decoupled from Combine so the audio tap thread only does cheap lock work,
/// not a @Published hop, on every buffer.
private struct WaveformView: View {
    let levelMeter: LevelMeter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
            let levels = levelMeter.snapshot()
            HStack(spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 3, height: barHeight(for: level))
                }
            }
            .frame(height: 44)
            .animation(.easeOut(duration: 0.1), value: levels)
        }
    }

    private func barHeight(for level: Float) -> CGFloat {
        let clamped = CGFloat(min(max(level, 0), 1))
        return 4 + clamped * 40
    }
}

private struct TranscriptText: View {
    let text: String
    let placeholder: String

    init(_ text: String, placeholder: String) {
        self.text = text
        self.placeholder = placeholder
    }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 15))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 140)
    }
}
