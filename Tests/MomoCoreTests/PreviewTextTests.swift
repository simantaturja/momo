import XCTest
@testable import MomoCore

final class PreviewTextTests: XCTestCase {
    func testCollapsesEmbeddedNewlinesToSingleSpace() {
        XCTAssertEqual(PreviewText.singleLine("Thomas\nMerge DN"), "Thomas Merge DN")
    }

    func testCollapsesRunsOfMixedWhitespaceAndTrimsEnds() {
        XCTAssertEqual(PreviewText.singleLine("  a\t\tb\r\n\nc  "), "a b c")
    }

    func testLeavesSingleLineUnchanged() {
        XCTAssertEqual(PreviewText.singleLine("git rebase -i HEAD~3"), "git rebase -i HEAD~3")
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(PreviewText.singleLine(""), "")
        XCTAssertEqual(PreviewText.singleLine("   \n\t "), "")
    }

    func testExcerptLeavesTextUpToTheLimitUntouched() {
        XCTAssertEqual(PreviewText.excerpt("hello", limit: 10), "hello")
        XCTAssertEqual(PreviewText.excerpt("hello", limit: 5), "hello")   // exactly the limit: no ellipsis
        XCTAssertEqual(PreviewText.excerpt(""), "")
    }

    func testExcerptCutsAtTheLimitInCharactersAndAddsEllipsis() {
        XCTAssertEqual(PreviewText.excerpt("hello world", limit: 5), "hello…")
        XCTAssertEqual(PreviewText.excerpt("🥟🥟🥟", limit: 2), "🥟🥟…")   // Characters, not UTF-16 units
        let long = PreviewText.excerpt(String(repeating: "a", count: 2_001))   // default limit is 2,000
        XCTAssertEqual(long, String(repeating: "a", count: 2_000) + "…")
    }

    func testFitsExcerptMeansExcerptKeepsTheWholeText() {
        XCTAssertTrue(PreviewText.fitsExcerpt("hello", limit: 5))
        XCTAssertTrue(PreviewText.fitsExcerpt("hello", limit: 10))
        XCTAssertTrue(PreviewText.fitsExcerpt(""))
        XCTAssertFalse(PreviewText.fitsExcerpt("hello!", limit: 5))
        XCTAssertTrue(PreviewText.fitsExcerpt(String(repeating: "a", count: 2_000)))    // default limit is 2,000
        XCTAssertFalse(PreviewText.fitsExcerpt(String(repeating: "a", count: 2_001)))
    }

    func testJoinedExcerptEqualsTheExcerptOfTheJoin() {
        XCTAssertEqual(PreviewText.joinedExcerpt(["ab", "cd"], limit: 10), "ab\ncd")
        XCTAssertEqual(PreviewText.joinedExcerpt(["ab", "c"], limit: 4), "ab\nc")      // exactly the limit
        XCTAssertEqual(PreviewText.joinedExcerpt(["abc", "def"], limit: 5), "abc\nd…")
        XCTAssertEqual(PreviewText.joinedExcerpt(["a", "b", "c"], limit: 4), "a\nb\n…")
        XCTAssertEqual(PreviewText.joinedExcerpt([]), "")
        let huge = String(repeating: "x", count: 5_000)
        XCTAssertEqual(PreviewText.joinedExcerpt([huge, "tail"]), PreviewText.excerpt(huge + "\ntail"))
    }

    func testHighlightRangesMergeConsecutiveOffsets() {
        XCTAssertEqual(PreviewText.highlightRanges(in: "abcd", positions: [0, 1, 3]),
                       [NSRange(location: 0, length: 2), NSRange(location: 3, length: 1)])
    }

    func testHighlightRangesAreUTF16() {
        // 🥟 is one Character but two UTF-16 units, so "a" (Character 1) starts at UTF-16 offset 2.
        XCTAssertEqual(PreviewText.highlightRanges(in: "🥟ab", positions: [1]), [NSRange(location: 2, length: 1)])
        XCTAssertEqual(PreviewText.highlightRanges(in: "🥟ab", positions: [0, 1]), [NSRange(location: 0, length: 3)])
    }

    func testHighlightRangesIgnoreOffsetsOutsideTheText() {
        XCTAssertEqual(PreviewText.highlightRanges(in: "ab", positions: [-1, 1, 5]), [NSRange(location: 1, length: 1)])
        XCTAssertEqual(PreviewText.highlightRanges(in: "ab", positions: [7]), [])
        XCTAssertEqual(PreviewText.highlightRanges(in: "ab", positions: []), [])
    }

    func testLineCount() {
        XCTAssertEqual(PreviewText.lineCount(""), 0)          // empty text has no lines
        XCTAssertEqual(PreviewText.lineCount("a"), 1)
        XCTAssertEqual(PreviewText.lineCount("a\nb"), 2)
        XCTAssertEqual(PreviewText.lineCount("a\r\nb"), 2)
        XCTAssertEqual(PreviewText.lineCount("a\n\nb"), 3)
        XCTAssertEqual(PreviewText.lineCount("a\n"), 1)       // a trailing line break ends a line, not starts one
    }
}
