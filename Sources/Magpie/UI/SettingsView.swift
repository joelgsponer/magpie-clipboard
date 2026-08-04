import SwiftUI

struct SettingsView: View {
    @AppStorage("historyCap") private var historyCap: Int = 500
    @State private var accessibilityTrusted: Bool = Accessibility.isTrusted

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Toggle history") {
                    Text("⌘⇧V")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
        .frame(width: 460)
        .padding()
        .onAppear {
            accessibilityTrusted = Accessibility.isTrusted
        }
    }
}
