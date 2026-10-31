import XCTest
@testable import MomoCore

final class HistoryIndexTests: XCTestCase {
    private func item(_ s: String, at t: TimeInterval, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s, text: s, imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: pinned,
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

    func testFuzzyMatchReturnsScoreAndMatchedPositions() {
        // g@0: 1 + 5, i@1: 10 + 4, t@2: 10 + 3 -> 33 (same score fuzzyScore reports)
        let contiguous = fuzzyMatch(query: "git", candidate: "github")
        XCTAssertEqual(contiguous?.score, 33)
        XCTAssertEqual(contiguous?.positions, [0, 1, 2])
        XCTAssertEqual(fuzzyScore(query: "git", candidate: "github"), 33)
        // Case-insensitive; g@0: 1 + 5, i@2: 1 + 3, t@4: 1 + 1 -> 12
        let scattered = fuzzyMatch(query: "GIT", candidate: "gxixt")
        XCTAssertEqual(scattered?.score, 12)
        XCTAssertEqual(scattered?.positions, [0, 2, 4])
        XCTAssertNil(fuzzyMatch(query: "xz", candidate: "github"))
    }

    func testSearchFiltersAndRanks() {
        let idx = HistoryIndex()
        idx.replaceAll([item("github.com", at: 3), item("gitlab", at: 2), item("banana", at: 1)])
        let results = idx.search("git")
        XCTAssertEqual(results.map(\.item.preview), ["github.com", "gitlab"]) // banana excluded, best first
    }

    func testEmptyQueryReturnsAllInOrder() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 2), item("b", at: 1)])
        XCTAssertEqual(idx.search("").map(\.item.preview), ["a", "b"])
    }

    func testPrependMovesDuplicateToFront() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 1), item("b", at: 2)])
        idx.prepend(item("a", at: 3))   // same content hash as existing "a"
        XCTAssertEqual(idx.search("").map(\.item.preview), ["a", "b"])
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
        XCTAssertEqual(front.item.id, existing.id)
    }

    func testPrependKeepsThePinOfTheItemItDedupes() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 2, pinned: true), item("b", at: 1)])
        idx.prepend(item("a", at: 3))   // a re-copy always arrives unpinned; Store.upsert keeps the pin
        XCTAssertEqual(idx.search("").map(\.item.pinned), [true, false])
        XCTAssertEqual(idx.search("", scope: .pinned).map(\.item.preview), ["a"])
    }

    func testPrependKeepsTheBlobOfTheImageItDedupes() {
        let image = { (path: String, t: TimeInterval) in
            ClipboardItem(kind: .image, preview: "Image", text: nil, imagePath: path, filePaths: [],
                          createdAt: Date(timeIntervalSince1970: t), pinned: false, contentHash: "same-bytes")
        }
        let idx = HistoryIndex()
        idx.replaceAll([image("stored.png", 1)])
        idx.prepend(image("incoming.png", 2))   // Store.upsert deletes the incoming blob on this hit
        XCTAssertEqual(idx.search("").map(\.item.imagePath), ["stored.png"])
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
        XCTAssertEqual(idx.search("", scope: .text).map(\.item.preview), ["hello"])
        XCTAssertEqual(idx.search("", scope: .images).map(\.item.preview), ["image"])
        XCTAssertEqual(idx.search("", scope: .files(extension: nil)).map(\.item.preview), ["/a.pdf"])
    }

    func testSearchFiltersByKindAndExtension() {
        let idx = HistoryIndex()
        idx.replaceAll([fileItem(["/a.pdf"], at: 2), fileItem(["/b.png"], at: 1)])
        XCTAssertEqual(idx.search("", scope: .files(extension: "pdf")).map(\.item.preview), ["/a.pdf"])
        XCTAssertEqual(idx.search("", scope: .files(extension: "png")).map(\.item.preview), ["/b.png"])
    }

    func testSearchCombinesTextQueryWithKindFilter() {
        let idx = HistoryIndex()
        idx.replaceAll([item("github.com", at: 3), item("gitlab", at: 2), fileItem(["/git.pdf"], at: 1)])
        // "git" fuzzy-matches all three previews' text, but scope: .text excludes the file item.
        XCTAssertEqual(idx.search("git", scope: .text).map(\.item.preview), ["github.com", "gitlab"])
    }

    func testAllScopeReturnsEveryKind() {
        let idx = HistoryIndex()
        idx.replaceAll([item("hello", at: 3), imageItem(at: 2), fileItem(["/a.pdf"], at: 1)])
        XCTAssertEqual(idx.search("", scope: .all).map(\.item.kind), [.text, .image, .file])
        XCTAssertEqual(idx.search("").map(\.item.kind), [.text, .image, .file])   // .all is the default
    }

    func testLinksScopeKeepsOnlyLinkText() {
        let idx = HistoryIndex()
        idx.replaceAll([item("https://github.com", at: 3), item("github notes", at: 2), fileItem(["/https.pdf"], at: 1)])
        XCTAssertEqual(idx.search("", scope: .links).map(\.item.preview), ["https://github.com"])
        XCTAssertEqual(idx.search("git", scope: .links).map(\.item.preview), ["https://github.com"])
    }

    func testPinnedScopeKeepsOnlyPinnedItems() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a", at: 3, pinned: true), item("b", at: 2), item("c", at: 1, pinned: true)])
        XCTAssertEqual(idx.search("", scope: .pinned).map(\.item.preview), ["a", "c"])
    }

    func testSearchMatchesTheSingleLineForm() {
        let idx = HistoryIndex()
        idx.replaceAll([item("a\nb", at: 1)])
        // The raw preview has a newline where the query has a space; the drawn line has a space.
        let rows = idx.search("a b")
        XCTAssertEqual(rows.map(\.item.preview), ["a\nb"])
        XCTAssertEqual(rows.first?.line, "a b")
    }

    func testMatchedPositionsIndexTheDrawnLine() {
        let idx = HistoryIndex()
        idx.replaceAll([item("x\n  hub", at: 1)])
        // line is "x hub": h@2 u@3 b@4 (the raw preview would give 4, 5, 6)
        XCTAssertEqual(idx.search("hub").first?.matchedPositions, [2, 3, 4])
        XCTAssertEqual(idx.search("").first?.matchedPositions, [])
    }

    func testRowsCarryFlavorDetectedFromTextItemsOnly() {
        let idx = HistoryIndex()
        idx.replaceAll([item("https://x.com", at: 4), item("#fff", at: 3), fileItem(["#abc"], at: 2)])
        idx.prepend(item("{ }", at: 5))
        // A file whose name looks like a color stays plain: flavor is only detected for .text.
        XCTAssertEqual(idx.search("").map(\.flavor), [.code, .link, .color, .plain])
    }

    /// A text item as ClipboardMonitor builds it: the preview is the trimmed text's first 200 characters.
    private func clip(_ text: String, at t: TimeInterval) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                      text: text, imagePath: nil, filePaths: [], createdAt: Date(timeIntervalSince1970: t), pinned: false,
                      contentHash: ClipboardItem.contentHash(kind: .text, text: text, imageHash: nil, filePaths: []))
    }

    func testLinkFlavorIsConfirmedAgainstTheFullText() {
        let longURL = "https://example.com/" + String(repeating: "a", count: 200)   // 220 characters
        let notALink = clip(longURL + " notes", at: 1)
        XCTAssertEqual(ContentFlavor.detect(notALink.preview), .link)   // its 200-character preview alone looks like one
        let idx = HistoryIndex()
        idx.replaceAll([notALink])
        idx.prepend(clip(longURL + "\n", at: 2))                        // a real long link stays a link
        XCTAssertEqual(idx.search("").map(\.flavor), [.link, .plain])
        XCTAssertEqual(idx.search("", scope: .links).map(\.item.text), [longURL + "\n"])
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
