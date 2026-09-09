import AppKit
import SwiftUI

struct CalcEntry: Identifiable, Equatable {
    let id = UUID()
    let expression: String
    let value: Double
}

@MainActor
final class CalculatorState: ObservableObject {
    @Published var input: String = ""
    @Published var tape: [CalcEntry] = []
    @Published var activationToken: Int = 0

    var lastValue: Double? { tape.last?.value }
}

@MainActor
final class CalculatorWindow {
    static let shared = CalculatorWindow()

    private var panel: NSPanel?
    private let state = CalculatorState()

    private init() {}

    func toggle() {
        if let panel, panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        Paster.shared.previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        state.input = ""
        state.activationToken += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func dismiss() {
        hide()
        if let target = Paster.shared.previousApp {
            NSApp.yieldActivation(to: target)
            target.activate()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel.make(width: 520, height: 360, autosaveName: "MagpieCalculatorPanel")
        let view = CalculatorView(
            onPaste: { [weak self] text in
                guard self?.panel?.isVisible == true else { return }
                self?.hide()
                HistoryStore.shared.ingest(kind: .text, text: text, sourceBundleID: "local.magpie")
                Paster.shared.insertText(text, mode: .paste)
            },
            onCopy: { [weak self] text in
                self?.dismiss()
                Paster.shared.copyText(text)
                HistoryStore.shared.ingest(kind: .text, text: text, sourceBundleID: "local.magpie")
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        .environmentObject(state)
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
