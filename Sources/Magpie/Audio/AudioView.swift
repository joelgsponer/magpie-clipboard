import CoreAudio
import SwiftUI

struct AudioView: View {
    @EnvironmentObject var state: AudioState
    @ObservedObject var audio: AudioDevices = .shared

    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                column(.output, title: "Output", devices: audio.outputs, current: audio.defaultOutput)
                Divider().opacity(0.4)
                column(.input, title: "Input", devices: audio.inputs, current: audio.defaultInput)
            }
            Divider().opacity(0.4)
            footer
            keyboardShortcuts
        }
        .frame(width: 680, height: 420)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: audio.devices.map(\.id)) { _, _ in clampIndex() }
        .onExitCommand { onClose() }
    }

    // MARK: - Header: the two level controls

    private var header: some View {
        HStack(spacing: 18) {
            levelControl(
                icon: audio.outputMuted ? "speaker.slash.fill" : speakerIcon(audio.outputVolume),
                label: "Output",
                value: audio.outputVolume,
                muted: audio.outputMuted,
                onChange: { audio.setOutputVolume($0) },
                onIconTap: { audio.toggleOutputMute() }
            )
            levelControl(
                icon: "mic.fill",
                label: "Input",
                value: audio.inputVolume,
                muted: false,
                onChange: { audio.setInputVolume($0) },
                onIconTap: nil
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func levelControl(
        icon: String, label: String, value: Float?, muted: Bool,
        onChange: @escaping (Float) -> Void, onIconTap: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Button { onIconTap?() } label: {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(muted ? Color.orange : Color.secondary)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .disabled(onIconTap == nil)

            Slider(
                value: Binding(get: { Double(value ?? 0) }, set: { onChange(Float($0)) }),
                in: 0...1
            )
            .controlSize(.small)
            .disabled(value == nil)
            .opacity(value == nil ? 0.4 : 1)

            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func speakerIcon(_ v: Float?) -> String {
        guard let v else { return "speaker.wave.2.fill" }
        if v == 0 { return "speaker.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Device columns

    private func column(_ which: AudioState.Column, title: String, devices: [AudioDevice], current: AudioDeviceID?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(state.column == which ? .primary : .tertiary)
                Spacer()
                Text("\(devices.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if devices.isEmpty {
                Text("No devices")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(devices.enumerated()), id: \.element.id) { i, device in
                            row(device, isDefault: device.id == current, highlighted: state.column == which && state.index == i)
                                .onTapGesture {
                                    state.column = which
                                    state.index = i
                                    activate(device, in: which)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { state.column = which }
    }

    private func row(_ device: AudioDevice, isDefault: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: isDefault ? .semibold : .regular))
                    .lineLimit(1)
                if !device.transportLabel.isEmpty {
                    Text(device.transportLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HintGroup(keys: ["↵"], description: "use device")
            HintGroup(keys: ["⇥"], description: "switch column")
            HintGroup(keys: ["-", "+"], description: "volume")
            HintGroup(keys: ["M"], description: "mute")
            HintGroup(keys: ["esc"], description: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: activateSelected).keyboardShortcut(.return, modifiers: [])
            Button("", action: { move(1) }).keyboardShortcut(.downArrow, modifiers: [])
            Button("", action: { move(-1) }).keyboardShortcut(.upArrow, modifiers: [])
            Button("", action: { switchColumn() }).keyboardShortcut(.tab, modifiers: [])
            Button("", action: { state.column = .input; clampIndex() }).keyboardShortcut(.rightArrow, modifiers: [])
            Button("", action: { state.column = .output; clampIndex() }).keyboardShortcut(.leftArrow, modifiers: [])
            Button("", action: { nudge(-0.05) }).keyboardShortcut("-", modifiers: [])
            Button("", action: { nudge(0.05) }).keyboardShortcut("=", modifiers: [])
            Button("", action: { nudge(0.05) }).keyboardShortcut("+", modifiers: [])
            Button("", action: { audio.toggleOutputMute() }).keyboardShortcut("m", modifiers: [])
            ForEach(1...9, id: \.self) { n in
                Button("", action: { pick(n - 1) })
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Actions

    private var currentList: [AudioDevice] {
        state.column == .output ? audio.outputs : audio.inputs
    }

    private func clampIndex() {
        let count = currentList.count
        state.index = count == 0 ? 0 : max(0, min(count - 1, state.index))
    }

    private func move(_ offset: Int) {
        let count = currentList.count
        guard count > 0 else { return }
        state.index = max(0, min(count - 1, state.index + offset))
    }

    private func switchColumn() {
        state.column = state.column == .output ? .input : .output
        let list = currentList
        let current = state.column == .output ? audio.defaultOutput : audio.defaultInput
        state.index = list.firstIndex { $0.id == current } ?? 0
    }

    private func activateSelected() {
        let list = currentList
        guard list.indices.contains(state.index) else { return }
        activate(list[state.index], in: state.column)
    }

    private func pick(_ i: Int) {
        let list = currentList
        guard list.indices.contains(i) else { return }
        state.index = i
        activate(list[i], in: state.column)
    }

    private func activate(_ device: AudioDevice, in column: AudioState.Column) {
        switch column {
        case .output: audio.setDefaultOutput(device.id)
        case .input: audio.setDefaultInput(device.id)
        }
    }

    private func nudge(_ delta: Float) {
        switch state.column {
        case .output: audio.nudgeOutputVolume(delta)
        case .input: audio.nudgeInputVolume(delta)
        }
    }
}
