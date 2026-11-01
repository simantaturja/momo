import XCTest
@testable import MomoCore

final class CopyDetailsTests: XCTestCase {
    private func item(_ kind: ItemKind, text: String? = nil, files: [String] = []) -> ClipboardItem {
        ClipboardItem(kind: kind, preview: text ?? "Image", text: text, imagePath: nil, filePaths: files,
                      createdAt: Date(timeIntervalSince1970: 50), pinned: false, contentHash: "h")
    }

    func testContentOfATextClipIsItsTrimmedText() {
        XCTAssertEqual(CopyDetails.content(of: item(.text, text: "  hello\n  world \n")), "hello\n  world")
    }

    func testContentOfALongTextClipIsCut() {
        let long = String(repeating: "a", count: CopyDetails.contentLimit + 10)
        XCTAssertEqual(CopyDetails.content(of: item(.text, text: long)),
                       String(repeating: "a", count: CopyDetails.contentLimit) + "…")
    }

    func testContentOfAManyLineTextClipKeepsItsFirstLines() {
        let lines = (1...12).map { "line \($0)" }
        XCTAssertEqual(CopyDetails.content(of: item(.text, text: lines.joined(separator: "\r\n"))),
                       lines.prefix(CopyDetails.maxLines).joined(separator: "\n") + "…")
        let exactlyMax = lines.prefix(CopyDetails.maxLines).joined(separator: "\n")
        XCTAssertEqual(CopyDetails.content(of: item(.text, text: exactlyMax)), exactlyMax)   // nothing cut
    }

    func testContentOfAFileClipListsItsPathsUpToALimit() {
        let paths = (1...7).map { NSHomeDirectory() + "/f\($0).txt" }
        XCTAssertEqual(CopyDetails.content(of: item(.file, files: paths)),
                       "~/f1.txt\n~/f2.txt\n~/f3.txt\n~/f4.txt\n~/f5.txt\nand 2 more")
    }

    func testContentOfAnImageClip() {
        XCTAssertEqual(CopyDetails.content(of: item(.image)), "Image")
    }

    func testFactsListEverythingKnownInOrder() {
        var copied = item(.text, text: "x")
        copied.sourceApp = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
        copied.firstCopiedAt = Date(timeIntervalSince1970: 10)
        copied.copyCount = 3
        XCTAssertEqual(CopyDetails.facts(of: copied), [
            .app(SourceApp(name: "Safari", bundleID: "com.apple.Safari")),
            .firstCopied(Date(timeIntervalSince1970: 10)),
            .lastCopied(Date(timeIntervalSince1970: 50)),
            .copies(3),
        ])
    }

    func testFactsLeaveOutWhatIsUnknown() {
        // An item recorded before Momo tracked copy history only knows when it was last copied.
        XCTAssertEqual(CopyDetails.facts(of: item(.text, text: "x")), [.lastCopied(Date(timeIntervalSince1970: 50))])
    }
}
