import XCTest
@testable import MomoCore

final class CombinedClipTests: XCTestCase {
    private func text(_ s: String?) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s ?? "", text: s, imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: 0), pinned: false, contentHash: "t-\(s ?? "")")
    }

    private func image(_ path: String?) -> ClipboardItem {
        ClipboardItem(kind: .image, preview: "Image", text: nil, imagePath: path, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: 0), pinned: false, contentHash: "i-\(path ?? "")")
    }

    private func file(_ paths: [String]) -> ClipboardItem {
        ClipboardItem(kind: .file, preview: paths.joined(separator: ", "), text: nil, imagePath: nil,
                      filePaths: paths, createdAt: Date(timeIntervalSince1970: 0), pinned: false,
                      contentHash: "f-\(paths.joined())")
    }

    func testJoinsTextItemsWithNewlinesInGivenOrder() {
        let clip = CombinedClip([text("a"), text("b"), text("c")])
        XCTAssertEqual(clip.text, "a\nb\nc")
        XCTAssertEqual(clip.filePaths, [])
        XCTAssertEqual(clip.imagePaths, [])
    }

    func testSingleTextItemIsCopiedVerbatim() {
        XCTAssertEqual(CombinedClip([text("multi\nline ")]).text, "multi\nline ")
    }

    func testFilePathsAreMergedInOrderWithoutDuplicates() {
        let clip = CombinedClip([file(["/a", "/b"]), file(["/b", "/c"])])
        XCTAssertEqual(clip.filePaths, ["/a", "/b", "/c"])
        XCTAssertNil(clip.text)
    }

    func testMixedKindsKeepEveryPayload() {
        let clip = CombinedClip([text("x"), image("1.png"), file(["/f"]), image("2.png"), text("y")])
        XCTAssertEqual(clip.text, "x\ny")
        XCTAssertEqual(clip.filePaths, ["/f"])
        XCTAssertEqual(clip.imagePaths, ["1.png", "2.png"])
        XCTAssertFalse(clip.isEmpty)
    }

    func testItemsWithoutPayloadProduceEmptyClip() {
        XCTAssertTrue(CombinedClip([text(nil), image(nil), file([])]).isEmpty)
        XCTAssertTrue(CombinedClip([]).isEmpty)
    }
}
