import Foundation

/// Subsequence fuzzy match. Returns nil if `query` is not a subsequence of
/// `candidate` (case-insensitive). Higher score = better: contiguous runs and
/// early matches are rewarded.
public func fuzzyScore(query: String, candidate: String) -> Int? {
    if query.isEmpty { return 0 }
    let q = Array(query.lowercased())
    let c = Array(candidate.lowercased())
    var qi = 0
    var score = 0
    var lastMatch = -2
    for (ci, ch) in c.enumerated() {
        if qi < q.count && ch == q[qi] {
            if ci == lastMatch + 1 { score += 10 } else { score += 1 } // contiguity bonus
            score += max(0, 5 - ci)                                    // earliness bonus
            lastMatch = ci
            qi += 1
        }
    }
    return qi == q.count ? score : nil
}
