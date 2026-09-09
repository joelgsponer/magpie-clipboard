import SwiftUI

/// Block-level markdown, enough for a chat reply: fenced code, headings,
/// bullet and numbered lists, block quotes, paragraphs. Inline styling
/// (bold, italic, code, links) inside each block comes from
/// AttributedString's own markdown parser.
enum MarkdownBlock: Identifiable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(items: [String])
    case numbered(items: [String])
    case quote(String)
    case code(language: String, text: String)

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l):\(t)"
        case .paragraph(let t): return "p:\(t)"
        case .bullet(let i): return "ul:\(i.joined(separator: "|"))"
        case .numbered(let i): return "ol:\(i.joined(separator: "|"))"
        case .quote(let t): return "q:\(t)"
        case .code(let l, let t): return "code:\(l):\(t)"
        }
    }

    static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quote: [String] = []
        var code: [String]? = nil
        var codeLang = ""

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullet(items: bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbered(items: numbers)); numbers = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: " "))); quote = [] }
        }

        for rawLine in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if var c = code {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(language: codeLang, text: c.joined(separator: "\n")))
                    code = nil
                } else {
                    c.append(line)
                    code = c
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                code = []
                continue
            }
            if trimmed.isEmpty { flush(); continue }
            if let m = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush()
                let level = trimmed[m].filter { $0 == "#" }.count
                blocks.append(.heading(level: level, text: String(trimmed[m.upperBound...])))
                continue
            }
            if let m = trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                if !paragraph.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
                bullets.append(String(trimmed[m.upperBound...]))
                continue
            }
            if let m = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                if !paragraph.isEmpty || !bullets.isEmpty || !quote.isEmpty { flush() }
                numbers.append(String(trimmed[m.upperBound...]))
                continue
            }
            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty || !numbers.isEmpty { flush() }
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if !bullets.isEmpty, line.hasPrefix("  ") {
                bullets[bullets.count - 1] += " " + trimmed
                continue
            }
            if !bullets.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let c = code { blocks.append(.code(language: codeLang, text: c.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MarkdownBlock.parse(markdown)) { block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: level <= 1 ? 17 : (level == 2 ? 15 : 13.5), weight: .semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            inline(text)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        inline(item)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                        inline(item)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                inline(text).foregroundStyle(.secondary)
            }
        case .code(let language, let text):
            CodeBlock(language: language, text: text)
        }
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}

private struct CodeBlock: View {
    let language: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    Paster.shared.copyText(text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider().opacity(0.3)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
