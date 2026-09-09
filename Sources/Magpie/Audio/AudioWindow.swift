import AppKit
import CoreAudio
import SwiftUI

@MainActor
final class AudioState: ObservableObject {
    enum Column { case output, input }
    @Published var column: Column = .output
    @Published var index: Int = 0
    @Published var activationToken: Int = 0
}

@MainActor
final class AudioWindow {
    static let shared = AudioWindow()

    private var panel: NSPanel?
    private let state = AudioState()
    private var previousApp: NSRunningApplication?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        AudioDevices.shared.refresh()

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Start on the current default output, the thing most often switched.
        let devices = AudioDevices.shared
        state.column = .output
        state.index = devices.outputs.firstIndex { $0.id == devices.defaultOutput } ?? 0
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

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel.make(width: 680, height: 420, autosaveName: "MagpieAudioPanel")
        let view = AudioView(onClose: { [weak self] in self?.dismiss() })
            .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
