import XCTest
@testable import PastalCore

final class ClipboardItemTests: XCTestCase {
    func testHashIsStableAndPayloadSensitive() {
        let a = ClipboardItem.contentHash(kind: .text, text: "hello", imagePath: nil, filePaths: [])
        let b = ClipboardItem.contentHash(kind: .text, text: "hello", imagePath: nil, filePaths: [])
        let c = ClipboardItem.contentHash(kind: .text, text: "world", imagePath: nil, filePaths: [])
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
