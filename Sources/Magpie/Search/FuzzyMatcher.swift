import Foundation

enum FuzzyMatcher {
    /// Returns nil if `query` is not a (case-insensitive) subsequence of `candidate`,
    /// otherwise an integer score where higher = better.
    static func score(query: String, in candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        // Original-case characters, materialised once. Indexing `candidate`
        // directly inside the loop below meant an index(offsetBy:) walk from
        // startIndex on every character — O(n²) per candidate, re-run over the
        // whole history on every keystroke. Note this deliberately is *not*
        // `c`: that one is lowercased, so isUppercase would never fire and the
        // camelCase bonus would silently die.
        let orig = Array(candidate)
        guard !c.isEmpty, q.count <= c.count else { return nil }

        var qi = 0
        var score = 0
        var prevMatchedIndex = -2
        var lastChar: Character? = nil

        for (i, ch) in c.enumerated() {
            // Lowercasing changes the character count for a handful of scripts,
            // so `orig` can be shorter than `c`. Fall back instead of trapping —
            // the previous index(offsetBy:) form would have crashed outright.
            let origChar: Character? = i < orig.count ? orig[i] : nil
            let prevWasBoundary = lastChar.map(isBoundary) ?? true
            let isCamelStart: Bool = {
                guard let prev = lastChar, let origChar else { return false }
                return prev.isLowercase && origChar.isUppercase
            }()
            lastChar = origChar ?? ch

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
