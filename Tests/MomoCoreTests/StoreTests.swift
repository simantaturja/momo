import XCTest
@testable import MomoCore

final class StoreTests: XCTestCase {
    private func makeStore() throws -> Store {
        try makeStoreWithDir().store
    }

    private func makeStoreWithDir() throws -> (store: Store, dir: String) {
        let dir = NSTemporaryDirectory() + "momo-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try Store(path: ":memory:", imagesDirectory: dir), dir)
    }

    private func textItem(_ s: String, at t: TimeInterval, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: s, text: s, imagePath: nil, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: pinned,
                      contentHash: ClipboardItem.contentHash(kind: .text, text: s, imageHash: nil, filePaths: []))
    }

    private func imageItem(path: String, hash: String, at t: TimeInterval,
                           pinned: Bool = false, preview: String = "Image") -> ClipboardItem {
        ClipboardItem(kind: .image, preview: preview, text: nil, imagePath: path, filePaths: [],
                      createdAt: Date(timeIntervalSince1970: t), pinned: pinned, contentHash: hash)
    }

    private func exists(_ dir: String, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(rel))
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

    func testFileItemsDedupeToTop() throws {
        let store = try makeStore()
        func fileItem(_ paths: [String], at t: TimeInterval) -> ClipboardItem {
            ClipboardItem(kind: .file, preview: paths.joined(separator: ", "), text: nil,
                          imagePath: nil, filePaths: paths, createdAt: Date(timeIntervalSince1970: t),
                          pinned: false,
                          contentHash: ClipboardItem.contentHash(kind: .file, text: nil, imageHash: nil, filePaths: paths))
        }
        try store.upsert(fileItem(["/a.txt"], at: 1))
        try store.upsert(fileItem(["/b.txt"], at: 2))
        try store.upsert(fileItem(["/a.txt"], at: 3))   // same paths as first, newer
        let recent = try store.recent(limit: 10)
        XCTAssertEqual(recent.map(\.preview), ["/a.txt", "/b.txt"])  // deduped, moved to top
        XCTAssertEqual(recent.count, 2)
    }

    func testReUpsertingSameImageReclaimsRedundantBlob() throws {
        let (store, dir) = try makeStoreWithDir()
        let data = Data(count: 32)
        let p1 = try store.writeImageBlob(data)
        let p2 = try store.writeImageBlob(data)
        XCTAssertNotEqual(p1, p2)
        // Same dedupe key (content hash), distinct blob files on disk.
        try store.upsert(imageItem(path: p1, hash: "img-hash", at: 1))
        try store.upsert(imageItem(path: p2, hash: "img-hash", at: 2))   // dedupe hit
        let recent = try store.recent(limit: 10)
        XCTAssertEqual(recent.count, 1, "same-hash image must dedupe to a single row")
        XCTAssertTrue(exists(dir, p1), "kept row's blob must survive")
        XCTAssertFalse(exists(dir, p2), "redundant incoming blob must be reclaimed, not orphaned")
    }

    func testPruneEnforcesImageByteCap() throws {
        let (store, dir) = try makeStoreWithDir()
        let bytes = Data(count: 100)
        var paths: [String] = []
        for i in 1...3 {
            let p = try store.writeImageBlob(bytes)
            paths.append(p)
            try store.upsert(imageItem(path: p, hash: "h\(i)", at: TimeInterval(i), preview: "img\(i)"))
        }
        // 300 bytes total; cap 150 -> evict oldest images until <= cap -> keep only newest.
        try store.prune(maxItems: .max, maxImageBytes: 150, imageMaxAge: .infinity, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(try store.recent(limit: 10).map(\.preview), ["img3"])
        XCTAssertFalse(exists(dir, paths[0]))
        XCTAssertFalse(exists(dir, paths[1]))
        XCTAssertTrue(exists(dir, paths[2]))
    }

    func testPruneAgesOutOldUnpinnedImagesOnly() throws {
        let (store, dir) = try makeStoreWithDir()
        let bytes = Data(count: 10)
        let oldUnpinned = try store.writeImageBlob(bytes)
        let oldPinned = try store.writeImageBlob(bytes)
        let recentImg = try store.writeImageBlob(bytes)
        try store.upsert(imageItem(path: oldUnpinned, hash: "a", at: 0, pinned: false, preview: "oldimg"))
        try store.upsert(imageItem(path: oldPinned, hash: "b", at: 0, pinned: true, preview: "oldpin"))
        try store.upsert(imageItem(path: recentImg, hash: "c", at: 1000, pinned: false, preview: "newimg"))
        try store.upsert(textItem("oldtext", at: 0))
        // now=1000, maxAge=100 -> cutoff 900: only non-pinned images older than cutoff are deleted.
        try store.prune(maxItems: .max, maxImageBytes: .max, imageMaxAge: 100, now: Date(timeIntervalSince1970: 1000))
        let previews = Set(try store.recent(limit: 10).map(\.preview))
        XCTAssertFalse(previews.contains("oldimg"), "old non-pinned image aged out")
        XCTAssertTrue(previews.contains("oldpin"), "old pinned image survives age-out")
        XCTAssertTrue(previews.contains("newimg"), "recent image survives")
        XCTAssertTrue(previews.contains("oldtext"), "text is never aged out")
        XCTAssertFalse(exists(dir, oldUnpinned), "aged-out blob removed from disk")
        XCTAssertTrue(exists(dir, oldPinned), "pinned blob retained on disk")
    }
}
