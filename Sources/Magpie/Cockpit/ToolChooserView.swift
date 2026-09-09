import SwiftUI

/// Weapon-wheel style tool picker: one card per tool, each with a big key
/// badge. Letter or click opens the tool; arrows move the highlight.
struct ToolChooserView: View {
    @EnvironmentObject var state: ToolChooserState

    var onPick: (Tool) -> Void
    var onHover: (Tool?) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ForEach(Tool.allCases) { tool in
                    ToolCard(tool: tool, highlighted: state.highlighted == tool)
                        .onTapGesture { onPick(tool) }
                        .onHover { inside in onHover(inside ? tool : nil) }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    keycap("⌘")
                    keycap("space")
                    Text("cockpit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                Spacer()
                HintGroup(keys: ["letter"], description: "open")
                HintGroup(keys: ["←", "→", "↵"], description: "browse")
                HintGroup(keys: ["esc"], description: "close")
            }
            .padding(.horizontal, 4)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear { pop() }
        .onChange(of: state.activationToken) { _, _ in pop() }
    }

    private func pop() {
        appeared = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            appeared = true
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}

private struct ToolCard: View {
    let tool: Tool
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tool.tint.opacity(0.95), tool.tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tool.tint.opacity(highlighted ? 0.55 : 0.25), radius: highlighted ? 14 : 8, y: 4)
                Image(systemName: tool.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .frame(width: 60, height: 60)

            VStack(spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(String(tool.letter).uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(highlighted ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(highlighted ? Color.white : Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .frame(width: 108, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(highlighted ? 0.10 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? tool.tint.opacity(0.9) : Color.white.opacity(0.06), lineWidth: highlighted ? 1.5 : 1)
        )
        .scaleEffect(highlighted ? 1.05 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: highlighted)
        .contentShape(Rectangle())
    }
}
