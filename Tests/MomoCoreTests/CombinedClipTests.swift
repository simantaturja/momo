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
        let clip = CombinedClip([text("c"), text("a"), text("b")])
        XCTAssertEqual(clip.text, "c\na\nb")
        XCTAssertEqual(clip.filePaths, [])
        XCTAssertEqual(clip.imagePaths, [])
    }

    func testSingleTextItemIsCopiedVerbatim() {
        XCTAssertEqual(CombinedClip([text("multi\nline ")]).text, "multi\nline ")
    }

    func testFilePathsAreMergedInOrderWithoutDuplicates() {
        let clip = CombinedClip([file(["/z", "/b"]), file(["/b", "/a"])])
        XCTAssertEqual(clip.filePaths, ["/z", "/b", "/a"])
        XCTAssertNil(clip.text)
    }

    func testMixedKindsKeepEveryPayload() {
        let clip = CombinedClip([text("y"), image("2.png"), file(["/f"]), image("1.png"), text("x")])
        XCTAssertEqual(clip.texts, ["y", "x"])
        XCTAssertEqual(clip.text, "y\nx")
        XCTAssertEqual(clip.filePaths, ["/f"])
        XCTAssertEqual(clip.imagePaths, ["2.png", "1.png"])
    }

    func testItemsWithoutPayloadProduceEmptyClip() {
        for clip in [CombinedClip([text(nil), image(nil), file([])]), CombinedClip([])] {
            XCTAssertEqual(clip.texts, [])
            XCTAssertNil(clip.text)
            XCTAssertEqual(clip.filePaths, [])
            XCTAssertEqual(clip.imagePaths, [])
        }
    }
}
