import Foundation

enum FuzzyMatcher {
    /// Returns nil if `query` is not a (case-insensitive) subsequence of `candidate`,
    /// otherwise an integer score where higher = better.
    static func score(query: String, in candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !c.isEmpty, q.count <= c.count else { return nil }

        var qi = 0
        var score = 0
        var prevMatchedIndex = -2
        var lastChar: Character? = nil

        for (i, ch) in c.enumerated() {
            let prevWasBoundary = lastChar.map(isBoundary) ?? true
            let isCamelStart: Bool = {
                guard let prev = lastChar else { return false }
                return prev.isLowercase && candidate[candidate.index(candidate.startIndex, offsetBy: i)].isUppercase
            }()
            lastChar = candidate[candidate.index(candidate.startIndex, offsetBy: i)]

            if qi < q.count, ch == q[qi] {
                if i == prevMatchedIndex + 1 { score += 10 }
                if prevWasBoundary || isCamelStart { score += 15 }
                if qi == 0 && i == 0 { score += 30 }
                prevMatchedIndex = i
                qi += 1
            }
        }

        guard qi == q.count else { return nil }

        if c.count >= q.count {
            // Contiguous-substring bonus.
            if let _ = String(c).range(of: String(q)) {
                score += 50
            }
        }

        score -= c.count // mild length penalty so shorter snippets win ties.
        return score
    }

    private static func isBoundary(_ ch: Character) -> Bool {
        if ch.isWhitespace { return true }
        return "_-/.\\:".contains(ch)
    }
}
