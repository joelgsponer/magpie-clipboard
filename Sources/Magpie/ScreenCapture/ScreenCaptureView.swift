import AppKit
import SwiftUI

struct ScreenCaptureView: View {
    @ObservedObject private var manager: ScreenCaptureManager = .shared
    @AppStorage("captureCommitMode") private var commitModeRaw: String = CaptureCommitMode.textOnly.rawValue

    var onClose: () -> Void
    /// (result, mode, paste) — paste false means copy to the pasteboard only.
    var onCommit: (ScreenCaptureResult, CaptureCommitMode, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)

            Divider().opacity(0.4)

            footer

            keyboardShortcuts
        }
        .frame(width: 560, height: 460)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch manager.state {
        case .idle, .selectingRegion:
            // Not normally reachable: the panel stays hidden while the
            // crosshair is up, and is dismissed when we return to idle.
            VStack(spacing: 10) {
                ProgressView()
                Text("Select a region…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

        case .analysing:
            VStack(spacing: 12) {
                ProgressView()
                // Named for what it does, not a neutral "Analysing…": this
                // ships pixels off the machine and the user should see that.
                Text("Sending to Claude…")
                    .font(.system(size: 13, weight: .medium))
                if let startedAt = manager.analysisStartedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(elapsed(from: startedAt, to: context.date))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .done(let result):
            resultView(result)

        case .error(let message, let recovery):
            VStack(spacing: 12) {
                Label("Capture failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                switch recovery {
                case .screenRecordingSettings:
                    Button("Open Screen Recording Settings") { Self.openScreenRecordingSettings() }
                case .magpieSettings:
                    Button("Open Magpie Settings…") { Self.openMagpieSettings() }
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func resultView(_ result: ScreenCaptureResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(result)

            VStack(alignment: .leading, spacing: 5) {
                sectionLabel("CONTEXT")
                Text(result.context)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 5) {
                sectionLabel("TEXT")
                if result.extractedText.isEmpty {
                    Text("No text found in this capture")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        Text(result.extractedText)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ result: ScreenCaptureResult) -> some View {
        HStack(spacing: 10) {
            if let image = NSImage(data: result.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text(subtitle(result))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func subtitle(_ result: ScreenCaptureResult) -> String {
        var parts = ["\(Int(result.pixelSize.width))×\(Int(result.pixelSize.height))"]
        if let cost = result.costUSD {
            parts.append(String(format: "$%.3f", cost))
        }
        return parts.joined(separator: " · ")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 14) {
            if case .done = manager.state {
                HintGroup(keys: ["↵"], description: "paste")
                HintGroup(keys: ["⌘", "↵"], description: "copy")
            }
            HintGroup(keys: ["esc"], description: "close")

            Spacer(minLength: 8)

            if case .done(let result) = manager.state {
                Picker("", selection: commitModeBinding) {
                    ForEach(CaptureCommitMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                // With no text there is nothing for .textOnly to put on the
                // pasteboard, so the choice is forced rather than offered.
                .disabled(result.extractedText.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Commit

    private var commitModeBinding: Binding<CaptureCommitMode> {
        Binding(
            get: { CaptureCommitMode(rawValue: commitModeRaw) ?? .textOnly },
            set: { commitModeRaw = $0.rawValue }
        )
    }

    private func effectiveMode(for result: ScreenCaptureResult) -> CaptureCommitMode {
        result.extractedText.isEmpty
            ? .withContext
            : (CaptureCommitMode(rawValue: commitModeRaw) ?? .textOnly)
    }

    private func commit(paste: Bool) {
        guard case .done(let result) = manager.state else { return }
        onCommit(result, effectiveMode(for: result), paste)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: { commit(paste: true) })
                .keyboardShortcut(.return, modifiers: [])
            Button("", action: { commit(paste: false) })
                .keyboardShortcut(.return, modifiers: .command)
            // Nothing here takes text-field focus, so onExitCommand alone
            // doesn't reliably catch Esc — same trick as DictationView.
            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Helpers

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func openMagpieSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Renamed in macOS 13; keep the older selector as a fallback.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
