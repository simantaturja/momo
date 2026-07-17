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

    private func fileItem(_ paths: [String], at t: TimeInterval) -> ClipboardItem {
        ClipboardItem(kind: .file, preview: paths.joined(separator: ", "), text: nil, imagePath: nil,
                      filePaths: paths, createdAt: Date(timeIntervalSince1970: t), pinned: false,
                      contentHash: ClipboardItem.contentHash(kind: .file, text: nil, imageHash: nil, filePaths: paths))
    }

    private func imageItem(at t: TimeInterval) -> ClipboardItem {
        ClipboardItem(kind: .image, preview: "image", text: nil, imagePath: "img.png", filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: false,
                      contentHash: ClipboardItem.contentHash(kind: .image, text: nil, imageHash: "h\(t)", filePaths: []))
    }

    func testSearchFiltersByKind() {
        let idx = HistoryIndex()
        idx.replaceAll([item("hello", at: 3), imageItem(at: 2), fileItem(["/a.pdf"], at: 1)])
        XCTAssertEqual(idx.search("", kind: .text).map(\.preview), ["hello"])
        XCTAssertEqual(idx.search("", kind: .image).map(\.preview), ["image"])
        XCTAssertEqual(idx.search("", kind: .file).map(\.preview), ["/a.pdf"])
    }

    func testSearchFiltersByKindAndExtension() {
        let idx = HistoryIndex()
        idx.replaceAll([fileItem(["/a.pdf"], at: 2), fileItem(["/b.png"], at: 1)])
        XCTAssertEqual(idx.search("", kind: .file, fileExtension: "pdf").map(\.preview), ["/a.pdf"])
        XCTAssertEqual(idx.search("", kind: .file, fileExtension: "png").map(\.preview), ["/b.png"])
    }

    func testSearchCombinesTextQueryWithKindFilter() {
        let idx = HistoryIndex()
        idx.replaceAll([item("github.com", at: 3), item("gitlab", at: 2), fileItem(["/git.pdf"], at: 1)])
        // "git" fuzzy-matches all three previews' text, but kind: .text excludes the file item.
        XCTAssertEqual(idx.search("git", kind: .text).map(\.preview), ["github.com", "gitlab"])
    }

    func testSearchWithNoKindArgumentBehavesAsBefore() {
        let idx = HistoryIndex()
        idx.replaceAll([item("github.com", at: 3), item("gitlab", at: 2), item("banana", at: 1)])
        XCTAssertEqual(idx.search("git"), idx.search("git", kind: nil, fileExtension: nil))
    }

    func testDistinctFileExtensionsEmptyWhenNoFileItems() {
        let idx = HistoryIndex()
        idx.replaceAll([item("hello", at: 1), imageItem(at: 2)])
        XCTAssertEqual(idx.distinctFileExtensions(), [])
    }

    func testDistinctFileExtensionsDedupesSortsAndLowercases() {
        let idx = HistoryIndex()
        idx.replaceAll([fileItem(["/a.PDF"], at: 3), fileItem(["/b.pdf"], at: 2), fileItem(["/c.png"], at: 1)])
        XCTAssertEqual(idx.distinctFileExtensions(), ["pdf", "png"])
    }

    func testDistinctFileExtensionsAcrossMultiPathItem() {
        let idx = HistoryIndex()
        idx.replaceAll([fileItem(["/a.txt", "/b.zip"], at: 1)])
        XCTAssertEqual(idx.distinctFileExtensions(), ["txt", "zip"])
    }
}
