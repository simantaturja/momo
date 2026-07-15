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
}
