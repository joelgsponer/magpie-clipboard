import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("historyCap") private var historyCap: Int = 500
    @AppStorage("captureModel") private var captureModel: String = "sonnet"
    @AppStorage("captureDisclosureAccepted") private var captureEnabled: Bool = false
    @AppStorage("claudeCLIPath") private var claudeCLIPathOverride: String = ""

    @State private var accessibilityTrusted: Bool = Accessibility.isTrusted
    @State private var screenRecordingTrusted: Bool = ScreenRecording.isTrusted
    @State private var resolvedClaudePath: String?
    @State private var resolving = false

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Toggle history") { shortcut("⌘⇧V") }
                LabeledContent("Emoji picker") { shortcut("⌘⇧E") }
                LabeledContent("Dictation") { shortcut("⌘⇧D") }
                LabeledContent("Screen capture") { shortcut("⌘⇧X") }
                Text("Rebinding is not available in v1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Stepper(value: $historyCap, in: 50...5000, step: 50) {
                    Text("Keep up to \(historyCap) unpinned items")
                }
                .onChange(of: historyCap) { _, new in
                    HistoryStore.shared.historyCap = new
                }
            }

            Section("Screen Capture") {
                Toggle("Send captures to Claude", isOn: $captureEnabled)
                Text("⌘⇧X selects a screen region and sends it to Anthropic's API, which returns the text it contains plus a short description. Unlike dictation, this does not run on your Mac — anything visible in the region is transmitted, at roughly $0.04 per capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: screenRecordingTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(screenRecordingTrusted ? .green : .orange)
                    Text(screenRecordingTrusted
                        ? "Screen Recording permission granted"
                        : "Screen Recording permission required")
                    Spacer()
                    if !screenRecordingTrusted {
                        Button("Grant…") {
                            ScreenRecording.requestIfNeeded()
                        }
                    }
                }
                if !screenRecordingTrusted {
                    Text("After granting, quit and reopen Magpie — macOS only applies this permission on relaunch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("claude CLI") {
                    Text(resolving ? "Detecting…" : (resolvedClaudePath ?? "Not found"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(resolvedClaudePath == nil && !resolving ? .orange : .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                HStack {
                    Button("Choose…") { chooseClaudePath() }
                    Button("Re-detect") { detectClaudePath() }
                        .disabled(resolving)
                    if !claudeCLIPathOverride.isEmpty {
                        Button("Clear override") {
                            claudeCLIPathOverride = ""
                            detectClaudePath()
                        }
                    }
                    Spacer()
                }

                Picker("Model", selection: $captureModel) {
                    Text("Haiku — cheapest").tag("haiku")
                    Text("Sonnet — recommended").tag("sonnet")
                    Text("Opus — most capable").tag("opus")
                }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted
                        ? "Accessibility permission granted"
                        : "Accessibility permission required for paste-back")
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Grant…") {
                            Accessibility.requestIfNeeded()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .onAppear {
            accessibilityTrusted = Accessibility.isTrusted
            screenRecordingTrusted = ScreenRecording.isTrusted
            detectClaudePath()
        }
    }

    private func shortcut(_ keys: String) -> some View {
        Text(keys)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// Resolution can fall through to a login-shell probe, which blocks for up
    /// to a few seconds — keep it off the main thread.
    private func detectClaudePath() {
        resolving = true
        DispatchQueue.global().async {
            let path = ClaudeCLI.resolve()
            DispatchQueue.main.async {
                resolvedClaudePath = path
                resolving = false
            }
        }
    }

    private func chooseClaudePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Select the claude executable"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        claudeCLIPathOverride = url.path
        detectClaudePath()
    }
}
