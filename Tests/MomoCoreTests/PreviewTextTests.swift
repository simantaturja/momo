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
}
