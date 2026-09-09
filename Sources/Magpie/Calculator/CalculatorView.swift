import SwiftUI

struct CalculatorView: View {
    @EnvironmentObject var state: CalculatorState

    var onPaste: (String) -> Void
    var onCopy: (String) -> Void
    var onClose: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider().opacity(0.4)
            resultPane
            Divider().opacity(0.4)
            tape
            Divider().opacity(0.4)
            footer
            keyboardShortcuts
        }
        .frame(width: 520, height: 360)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { inputFocused = true }
        .onChange(of: state.activationToken) { _, _ in inputFocused = true }
        .onExitCommand { onClose() }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "function")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("2^10 / 3, sqrt(2), 15% of 80 → 80*15%, ans*2", text: $state.input)
                .textFieldStyle(.plain)
                .font(.system(size: 18, design: .monospaced))
                .focused($inputFocused)
                .onSubmit { commit(paste: true) }
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultPane: some View {
        HStack {
            Spacer()
            switch evaluation {
            case .empty:
                Text(state.lastValue.map { "ans = \(ExpressionEvaluator.format($0))" } ?? "0")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.tertiary)
            case .value(let v):
                Text(ExpressionEvaluator.formatGrouped(v))
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            case .error(let message):
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(height: 84)
    }

    @ViewBuilder
    private var tape: some View {
        if state.tape.isEmpty {
            VStack(spacing: 6) {
                Text("Enter pastes the result into the app you came from.")
                Text("Functions: sqrt, ln, log, sin, cos, tan, abs, round, min, max, avg, fact · constants: pi, e, ans")
                    .multilineTextAlignment(.center)
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.tape) { entry in
                            HStack {
                                Text(entry.expression)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("= " + ExpressionEvaluator.formatGrouped(entry.value))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { state.input = ExpressionEvaluator.format(entry.value) }
                            .id(entry.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: state.tape.count) { _, _ in
                    if let last = state.tape.last { proxy.scrollTo(last.id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            HintGroup(keys: ["↵"], description: "paste result")
            HintGroup(keys: ["⌘", "↵"], description: "copy")
            HintGroup(keys: ["⇧", "↵"], description: "keep & continue")
            HintGroup(keys: ["⌘", "K"], description: "clear tape")
            HintGroup(keys: ["esc"], description: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var keyboardShortcuts: some View {
        VStack {
            Button("", action: { commit(paste: false, copy: true) }).keyboardShortcut(.return, modifiers: .command)
            Button("", action: { commit(paste: false) }).keyboardShortcut(.return, modifiers: .shift)
            Button("", action: { state.tape.removeAll() }).keyboardShortcut("k", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Evaluation

    private enum Evaluation {
        case empty
        case value(Double)
        case error(String)
    }

    private var evaluation: Evaluation {
        let text = state.input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .empty }
        do {
            return .value(try ExpressionEvaluator.evaluate(text, ans: state.lastValue))
        } catch ExpressionEvaluator.EvalError.empty {
            return .empty
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Enter with an empty input re-uses the previous answer, so a chain of
    /// "↵" after "⇧↵" pastes the running total.
    private func commit(paste: Bool, copy: Bool = false) {
        let value: Double
        let expression: String
        switch evaluation {
        case .value(let v):
            value = v
            expression = state.input.trimmingCharacters(in: .whitespaces)
        case .empty:
            guard let last = state.lastValue else { return }
            value = last
            expression = "ans"
        case .error:
            return
        }
        if expression != "ans" {
            state.tape.append(CalcEntry(expression: expression, value: value))
        }
        let text = ExpressionEvaluator.format(value)
        state.input = ""
        if paste { onPaste(text) } else if copy { onCopy(text) }
    }
}
