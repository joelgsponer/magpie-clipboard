import Foundation

/// A small arithmetic evaluator: + - * / ^ %, parentheses, unary minus,
/// functions, constants, and `ans` for the previous result. Recursive
/// descent, no NSExpression — its grammar is a poor fit (no `^`, no unary
/// percent, cryptic errors).
enum ExpressionEvaluator {
    enum EvalError: Error, LocalizedError {
        case unexpected(String)
        case unknownIdentifier(String)
        case divisionByZero
        case empty

        var errorDescription: String? {
            switch self {
            case .unexpected(let t): return "Unexpected \"\(t)\""
            case .unknownIdentifier(let n): return "Unknown \"\(n)\""
            case .divisionByZero: return "Division by zero"
            case .empty: return ""
            }
        }
    }

    static func evaluate(_ source: String, ans: Double? = nil) throws -> Double {
        var parser = Parser(tokens: try Lexer.tokenize(source), ans: ans)
        guard !parser.tokens.isEmpty else { throw EvalError.empty }
        let value = try parser.expression()
        if let t = parser.peek() { throw EvalError.unexpected(t.text) }
        return value
    }

    // MARK: - Lexer

    fileprivate enum Token: Equatable {
        case number(Double, String)
        case ident(String)
        case op(Character)
        case lparen, rparen, comma

        var text: String {
            switch self {
            case .number(_, let s): return s
            case .ident(let s): return s
            case .op(let c): return String(c)
            case .lparen: return "("
            case .rparen: return ")"
            case .comma: return ","
            }
        }
    }

    fileprivate enum Lexer {
        static func tokenize(_ s: String) throws -> [Token] {
            var out: [Token] = []
            let chars = Array(s)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace || c == "_" {
                    i += 1
                    continue
                }
                if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                    var j = i
                    var text = ""
                    while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_"
                        || (chars[j] == "," && isThousandsComma(chars, j)) {
                        if chars[j] != "_" && chars[j] != "," { text.append(chars[j]) }
                        j += 1
                    }
                    // Exponent: 1e6, 2.5E-3
                    if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                        var k = j + 1
                        if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                        if k < chars.count, chars[k].isNumber {
                            text.append("e")
                            if chars[j + 1] == "-" { text.append("-") }
                            while k < chars.count, chars[k].isNumber { text.append(chars[k]); k += 1 }
                            j = k
                        }
                    }
                    guard let v = Double(text) else { throw EvalError.unexpected(text) }
                    out.append(.number(v, text))
                    i = j
                    continue
                }
                if c.isLetter {
                    var j = i
                    var text = ""
                    while j < chars.count, chars[j].isLetter || chars[j].isNumber { text.append(chars[j]); j += 1 }
                    out.append(.ident(text.lowercased()))
                    i = j
                    continue
                }
                switch c {
                case "+", "-", "*", "/", "^", "%": out.append(.op(c))
                case "×", "·": out.append(.op("*"))
                case "÷": out.append(.op("/"))
                case "−": out.append(.op("-"))
                case "(": out.append(.lparen)
                case ")": out.append(.rparen)
                case ",": out.append(.comma)
                default: throw EvalError.unexpected(String(c))
                }
                i += 1
            }
            return out
        }

        /// "1,000" is a thousands separator; "max(1, 2)" is an argument comma.
        /// A thousands comma sits between a digit and exactly three digits.
        private static func isThousandsComma(_ chars: [Character], _ i: Int) -> Bool {
            guard chars[i] == ",", i > 0, chars[i - 1].isNumber, i + 3 < chars.count else { return false }
            for k in 1...3 where !chars[i + k].isNumber { return false }
            if i + 4 < chars.count, chars[i + 4].isNumber { return false }
            return true
        }
    }

    // MARK: - Parser

    fileprivate struct Parser {
        let tokens: [Token]
        let ans: Double?
        var pos = 0

        init(tokens: [Token], ans: Double?) {
            self.tokens = tokens
            self.ans = ans
        }

        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        mutating func next() -> Token? {
            defer { pos += 1 }
            return peek()
        }

        // expression := term (('+' | '-') term)*
        mutating func expression() throws -> Double {
            var value = try term()
            while case .op(let c)? = peek(), c == "+" || c == "-" {
                pos += 1
                let rhs = try term()
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // term := unary (('*' | '/' | '%') unary)*   (with `x % y` = modulo, `x%` = percent)
        mutating func term() throws -> Double {
            var value = try unary()
            while true {
                guard case .op(let c)? = peek(), c == "*" || c == "/" || c == "%" else { break }
                if c == "%" {
                    // Postfix percent when nothing operand-like follows.
                    let after = pos + 1 < tokens.count ? tokens[pos + 1] : nil
                    let hasOperand: Bool = {
                        switch after {
                        case .number, .ident, .lparen: return true
                        default: return false
                        }
                    }()
                    if !hasOperand {
                        pos += 1
                        value /= 100
                        continue
                    }
                }
                pos += 1
                let rhs = try unary()
                switch c {
                case "*": value *= rhs
                case "/":
                    guard rhs != 0 else { throw EvalError.divisionByZero }
                    value /= rhs
                default:
                    guard rhs != 0 else { throw EvalError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        // unary := ('-' | '+') unary | power
        mutating func unary() throws -> Double {
            if case .op(let c)? = peek(), c == "-" || c == "+" {
                pos += 1
                let v = try unary()
                return c == "-" ? -v : v
            }
            return try power()
        }

        // power := postfix ('^' unary)?   (right-assoc)
        mutating func power() throws -> Double {
            let base = try postfix()
            if case .op("^")? = peek() {
                pos += 1
                let exp = try unary()
                return pow(base, exp)
            }
            return base
        }

        // postfix := primary ('!')?  — factorial via ident-less '!' is not lexed; keep hook for '%' handled in term
        mutating func postfix() throws -> Double {
            try primary()
        }

        // primary := number | ident | ident '(' args ')' | '(' expression ')'
        mutating func primary() throws -> Double {
            guard let t = next() else { throw EvalError.unexpected("end") }
            switch t {
            case .number(let v, _):
                return v
            case .lparen:
                let v = try expression()
                guard case .rparen? = next() else { throw EvalError.unexpected("missing )") }
                return v
            case .ident(let name):
                if case .lparen? = peek() {
                    pos += 1
                    var args: [Double] = []
                    if case .rparen? = peek() {
                        pos += 1
                    } else {
                        args.append(try expression())
                        while case .comma? = peek() {
                            pos += 1
                            args.append(try expression())
                        }
                        guard case .rparen? = next() else { throw EvalError.unexpected("missing )") }
                    }
                    return try call(name, args)
                }
                return try constant(name)
            default:
                throw EvalError.unexpected(t.text)
            }
        }

        func constant(_ name: String) throws -> Double {
            switch name {
            case "pi", "π": return .pi
            case "e": return M_E
            case "tau": return 2 * .pi
            case "ans":
                guard let ans else { throw EvalError.unknownIdentifier("ans") }
                return ans
            default: throw EvalError.unknownIdentifier(name)
            }
        }

        func call(_ name: String, _ a: [Double]) throws -> Double {
            func one() throws -> Double {
                guard a.count == 1 else { throw EvalError.unexpected("\(name) takes 1 argument") }
                return a[0]
            }
            switch name {
            case "sqrt": return (try one()).squareRoot()
            case "cbrt": return cbrt(try one())
            case "abs": return abs(try one())
            case "floor": return floor(try one())
            case "ceil": return ceil(try one())
            case "round":
                if a.count == 2 {
                    let f = pow(10, a[1])
                    return (a[0] * f).rounded() / f
                }
                return (try one()).rounded()
            case "ln": return log(try one())
            case "log", "log10": return log10(try one())
            case "log2": return log2(try one())
            case "exp": return exp(try one())
            case "sin": return sin(try one())
            case "cos": return cos(try one())
            case "tan": return tan(try one())
            case "asin": return asin(try one())
            case "acos": return acos(try one())
            case "atan": return atan(try one())
            case "min":
                guard let m = a.min() else { throw EvalError.unexpected("min()") }
                return m
            case "max":
                guard let m = a.max() else { throw EvalError.unexpected("max()") }
                return m
            case "avg", "mean":
                guard !a.isEmpty else { throw EvalError.unexpected("avg()") }
                return a.reduce(0, +) / Double(a.count)
            case "sum": return a.reduce(0, +)
            case "fact", "factorial":
                let n = try one()
                guard n >= 0, n == n.rounded(), n <= 170 else { throw EvalError.unexpected("factorial of \(n)") }
                return (1...max(1, Int(n))).reduce(1.0) { $0 * Double($1) }
            default:
                throw EvalError.unknownIdentifier(name)
            }
        }
    }

    // MARK: - Formatting

    /// Plain, paste-friendly: no grouping, up to 12 significant digits,
    /// trailing zeros trimmed, scientific only for the very large or small.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "undefined" : (value > 0 ? "∞" : "-∞") }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.6g", value)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.maximumSignificantDigits = 13
        f.usesSignificantDigits = true
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Grouped for display only.
    static func formatGrouped(_ value: Double) -> String {
        let plain = format(value)
        guard plain.first?.isNumber == true || plain.first == "-",
              !plain.contains("e"),
              let v = Double(plain) else { return plain }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = "\u{2009}"
        f.maximumFractionDigits = 10
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: v)) ?? plain
    }
}
