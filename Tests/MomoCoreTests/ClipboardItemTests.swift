import XCTest
@testable import MomoCore

final class ClipboardItemTests: XCTestCase {
    func testHashIsStableAndPayloadSensitive() {
        let a = ClipboardItem.contentHash(kind: .text, text: "hello", imageHash: nil, filePaths: [])
        let b = ClipboardItem.contentHash(kind: .text, text: "hello", imageHash: nil, filePaths: [])
        let c = ClipboardItem.contentHash(kind: .text, text: "world", imageHash: nil, filePaths: [])
        XCTAssertEqual(a, b)          // same payload -> same hash
        XCTAssertNotEqual(a, c)       // different payload -> different hash
    }

    func testEquatableByValue() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 0)
        func make() -> ClipboardItem {
            ClipboardItem(id: id, kind: .text, preview: "hi", text: "hi",
                          imagePath: nil, filePaths: [], createdAt: date,
                          pinned: false, contentHash: "x")
        }
        XCTAssertEqual(make(), make())
    }

    private func fileItem(paths: [String]) -> ClipboardItem {
        ClipboardItem(kind: .file, preview: paths.joined(separator: ", "), text: nil,
                      imagePath: nil, filePaths: paths, createdAt: Date(timeIntervalSince1970: 0),
                      pinned: false, contentHash: "file-\(paths.joined())")
    }

    private func textItem() -> ClipboardItem {
        ClipboardItem(kind: .text, preview: "hi", text: "hi", imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: 0), pinned: false, contentHash: "text-hi")
    }

    func testMatchesNilKindMatchesAnything() {
        XCTAssertTrue(textItem().matches(kind: nil, fileExtension: nil))
        XCTAssertTrue(fileItem(paths: ["/a.pdf"]).matches(kind: nil, fileExtension: nil))
    }

    func testMatchesKindOnly() {
        XCTAssertTrue(textItem().matches(kind: .text, fileExtension: nil))
        XCTAssertFalse(textItem().matches(kind: .image, fileExtension: nil))
        XCTAssertFalse(textItem().matches(kind: .file, fileExtension: nil))
    }

    func testMatchesFileWithNoExtensionFilterMatchesAnyFile() {
        XCTAssertTrue(fileItem(paths: ["/a.pdf"]).matches(kind: .file, fileExtension: nil))
        XCTAssertTrue(fileItem(paths: ["/a.PNG"]).matches(kind: .file, fileExtension: nil))
    }

    func testMatchesFileWithExtensionIsCaseInsensitive() {
        XCTAssertTrue(fileItem(paths: ["/a.PDF"]).matches(kind: .file, fileExtension: "pdf"))
        XCTAssertTrue(fileItem(paths: ["/a.pdf"]).matches(kind: .file, fileExtension: "PDF"))
        XCTAssertFalse(fileItem(paths: ["/a.pdf"]).matches(kind: .file, fileExtension: "png"))
    }

    func testMatchesFileWithMultiplePathsMatchesIfAnyExtensionMatches() {
        let item = fileItem(paths: ["/a.txt", "/b.pdf"])
        XCTAssertTrue(item.matches(kind: .file, fileExtension: "pdf"))
        XCTAssertTrue(item.matches(kind: .file, fileExtension: "txt"))
        XCTAssertFalse(item.matches(kind: .file, fileExtension: "png"))
    }

    func testMatchesFileExtensionIgnoredForNonFileKind() {
        // A non-file item never matches a file-extension filter, regardless of kind match.
        XCTAssertFalse(textItem().matches(kind: .text, fileExtension: "pdf"))
    }
}
