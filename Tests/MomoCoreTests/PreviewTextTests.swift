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
