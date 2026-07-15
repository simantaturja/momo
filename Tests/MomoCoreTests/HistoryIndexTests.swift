import XCTest
@testable import MomoCore

final class HistoryIndexTests: XCTestCase {
    private func item(_ s: String, at t: TimeInterval) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s, text: s, imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: false,
                      contentHash: ClipboardItem.contentHash(kind: .text, text: s, imageHash: nil, filePaths: []))
    }

    func testFuzzySubsequenceMatches() {
        XCTAssertNotNil(fuzzyScore(query: "gh", candidate: "github"))
        XCTAssertNil(fuzzyScore(query: "xz", candidate: "github"))
    }

    func testContiguousScoresHigherThanScattered() {
        let contiguous = fuzzyScore(query: "git", candidate: "github")!
        let scattered = fuzzyScore(query: "git", candidate: "gxixt")!
        XCTAssertGreaterThan(contiguous, scattered)
    }

    func testSearchFiltersAndRanks() {
        let idx = HistoryIndex()
        idx.replaceAll([item("github.com", at: 3), item("gitlab", at: 2), item("banana", at: 1)])
        let results = idx.search("git")
        XCTAssertEqual(results.map(\.preview), ["github.com", "gitlab"]) // banana excluded, best first
    }

    func testEmptyQueryReturnsAllInOrder() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 2), item("b", at: 1)])
        XCTAssertEqual(idx.search("").map(\.preview), ["a", "b"])
    }

    func testPrependMovesDuplicateToFront() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 1), item("b", at: 2)])
        idx.prepend(item("a", at: 3))   // same content hash as existing "a"
        XCTAssertEqual(idx.search("").map(\.preview), ["a", "b"])
        XCTAssertEqual(idx.search("").count, 2)
    }

    func testPrependReusesExistingIdOnDuplicate() {
        let idx = HistoryIndex()
        let existing = item("a", at: 1)
        idx.replaceAll([existing, item("b", at: 2)])
        let incoming = ClipboardItem(id: UUID(), kind: .text, preview: "a", text: "a",
                                      imagePath: nil, filePaths: [], createdAt: Date(timeIntervalSince1970: 3),
                                      pinned: false, contentHash: existing.contentHash)
        XCTAssertNotEqual(incoming.id, existing.id)
        idx.prepend(incoming)
        let front = idx.search("").first!
        XCTAssertEqual(front.id, existing.id)
    }
}
