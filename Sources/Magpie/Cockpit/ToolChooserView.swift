import AppKit
import SwiftUI

/// Weapon-wheel tool picker: every tool on a ring, a wedge behind each, and
/// a hub in the middle that names whatever is highlighted. Letter, click,
/// arrow keys, or pointing the mouse at a wedge all select.
struct ToolChooserView: View {
    @EnvironmentObject var state: ToolChooserState

    var onPick: (Tool) -> Void

    @State private var appeared = false

    static let size: CGFloat = 560
    static let ringRadius: CGFloat = 178      // where the tool tiles sit
    static let wedgeInner: CGFloat = 104
    static let wedgeOuter: CGFloat = 256
    static let hubRadius: CGFloat = 92

    var body: some View {
        ZStack {
            wedges
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                ToolTile(tool: tool, highlighted: state.highlighted == tool)
                    .position(Self.position(of: index, radius: Self.ringRadius))
                    .onTapGesture { onPick(tool) }
            }
            hub
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    HintGroup(keys: ["letter"], description: "open")
                    HintGroup(keys: ["←", "→", "↵"], description: "browse")
                    HintGroup(keys: ["esc"], description: "close")
                }
                .padding(.bottom, 44)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .background(
            Circle()
                .fill(.regularMaterial)
                .padding(10)
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .padding(10)
        )
        .scaleEffect(appeared ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : -6))
        .onAppear { pop() }
        .onChange(of: state.activationToken) { _, _ in pop() }
    }

    private func pop() {
        appeared = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) {
            appeared = true
        }
    }

    // MARK: - Geometry

    static var step: Double { 360 / Double(Tool.allCases.count) }

    /// Angle in SwiftUI's frame (0° = right, clockwise, y down); tool 0 at top.
    static func angle(of index: Int) -> Angle {
        .degrees(-90 + step * Double(index))
    }

    static func position(of index: Int, radius: CGFloat) -> CGPoint {
        let a = angle(of: index).radians
        return CGPoint(x: size / 2 + radius * cos(a), y: size / 2 + radius * sin(a))
    }

    /// Which tool a point (in this view's coordinates) lies on, if any:
    /// inside the ring band, sector by angle.
    static func tool(at point: CGPoint) -> Tool? {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= hubRadius, distance <= wedgeOuter + 8 else { return nil }
        var degrees = atan2(dy, dx) * 180 / .pi + 90   // 0 at top, clockwise
        if degrees < 0 { degrees += 360 }
        let index = Int((degrees + step / 2) / step) % Tool.allCases.count
        return Tool.allCases[index]
    }

    // MARK: - Pieces

    private var wedges: some View {
        Canvas { context, _ in
            let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
            let gap = 1.6
            for (index, tool) in Tool.allCases.enumerated() {
                let mid = Self.angle(of: index).degrees
                let start = Angle.degrees(mid - Self.step / 2 + gap)
                let end = Angle.degrees(mid + Self.step / 2 - gap)
                var path = Path()
                path.addArc(center: center, radius: Self.wedgeOuter, startAngle: start, endAngle: end, clockwise: false)
                path.addArc(center: center, radius: Self.wedgeInner, startAngle: end, endAngle: start, clockwise: true)
                path.closeSubpath()
                let highlighted = state.highlighted == tool
                context.fill(path, with: .color(tool.tint.opacity(highlighted ? 0.30 : 0.09)))
                context.stroke(path, with: .color(highlighted ? tool.tint.opacity(0.9) : Color.white.opacity(0.06)), lineWidth: highlighted ? 1.5 : 1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.highlighted)
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(.thickMaterial)
                .frame(width: Self.hubRadius * 2, height: Self.hubRadius * 2)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: Self.hubRadius * 2, height: Self.hubRadius * 2)

            if let tool = state.highlighted {
                VStack(spacing: 6) {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(tool.tint)
                    Text(tool.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(tool.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("press \(String(tool.letter).uppercased())")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .id(tool)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        keycap("⌘")
                        keycap("space")
                    }
                    Text("COCKPIT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: state.highlighted)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
    }
}

private struct ToolTile: View {
    let tool: Tool
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tool.tint.opacity(0.95), tool.tint.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: tool.tint.opacity(highlighted ? 0.6 : 0.22), radius: highlighted ? 14 : 6, y: 3)
                Image(systemName: tool.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .frame(width: 50, height: 50)

            Text(tool.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlighted ? .primary : .secondary)
                .lineLimit(1)

            Text(String(tool.letter).uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(highlighted ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(highlighted ? Color.white : Color.white.opacity(0.14))
                )
        }
        .scaleEffect(highlighted ? 1.12 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: highlighted)
        .contentShape(Rectangle())
    }
}
