import XCTest
@testable import PastalCore

final class StoreTests: XCTestCase {
    private func makeStore() throws -> Store {
        let dir = NSTemporaryDirectory() + "pastal-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return try Store(path: ":memory:", imagesDirectory: dir)
    }

    private func textItem(_ s: String, at t: TimeInterval, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s, text: s, imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: pinned,
                      contentHash: ClipboardItem.contentHash(kind: .text, text: s, imagePath: nil, filePaths: []))
    }

    func testInsertAndRecent() throws {
        let store = try makeStore()
        try store.upsert(textItem("a", at: 1))
        try store.upsert(textItem("b", at: 2))
        let recent = try store.recent(limit: 10)
        XCTAssertEqual(recent.map(\.preview), ["b", "a"])   // newest first
    }

    func testDedupeMovesToTopNoDuplicate() throws {
        let store = try makeStore()
        try store.upsert(textItem("a", at: 1))
        try store.upsert(textItem("b", at: 2))
        try store.upsert(textItem("a", at: 3))   // same content as first, newer
        let recent = try store.recent(limit: 10)
        XCTAssertEqual(recent.map(\.preview), ["a", "b"])  // "a" moved to top, no dup
        XCTAssertEqual(recent.count, 2)
    }

    func testPruneRespectsCountAndPins() throws {
        let store = try makeStore()
        try store.upsert(textItem("pinned", at: 1, pinned: true))
        for i in 2...6 { try store.upsert(textItem("n\(i)", at: TimeInterval(i))) }
        try store.prune(maxItems: 2, maxImageBytes: .max, imageMaxAge: .infinity, now: Date(timeIntervalSince1970: 100))
        let recent = try store.recent(limit: 10)
        XCTAssertTrue(recent.contains { $0.pinned })          // pin survived
        XCTAssertEqual(recent.filter { !$0.pinned }.count, 2) // only 2 non-pinned kept (newest)
        XCTAssertEqual(recent.filter { !$0.pinned }.map(\.preview), ["n6", "n5"])
    }
}
