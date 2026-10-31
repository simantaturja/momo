import Foundation

/// Subsequence fuzzy match. Returns nil if `query` is not a subsequence of
/// `candidate` (case-insensitive). Higher score = better: contiguous runs and
/// early matches are rewarded.
public func fuzzyScore(query: String, candidate: String) -> Int? {
    fuzzyMatch(query: query, candidate: candidate)?.score
}

/// `fuzzyScore` plus the offsets of the matched characters, for highlighting. Offsets index
/// `Array(candidate.lowercased())`, which for normal text are the Character offsets in
/// `candidate` (they differ only if lowercasing changes the Character count, which is rare).
public func fuzzyMatch(query: String, candidate: String) -> (score: Int, positions: [Int])? {
    if query.isEmpty { return (score: 0, positions: []) }
    let q = Array(query.lowercased())
    let c = Array(candidate.lowercased())
    var qi = 0
    var score = 0
    var lastMatch = -2
    var positions: [Int] = []
    for (ci, ch) in c.enumerated() {
        if qi < q.count && ch == q[qi] {
            if ci == lastMatch + 1 { score += 10 } else { score += 1 } // contiguity bonus
            score += max(0, 5 - ci)                                    // earliness bonus
            lastMatch = ci
            positions.append(ci)
            qi += 1
        }
    }
    return qi == q.count ? (score: score, positions: positions) : nil
}
