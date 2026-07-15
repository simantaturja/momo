import XCTest
@testable import MomoCore

private final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var types: Set<String> = ["public.utf8-plain-text"]
    var stringValue: String?
    var imageBytes: Data?
    func string() -> String? { stringValue }
    func imageData() -> Data? { imageBytes }
    func fileURLs() -> [String] { [] }
}

final class ClipboardMonitorTests: XCTestCase {
    func testNoEmitWhenChangeCountUnchanged() {
        let pb = FakePasteboard()
        pb.changeCount = 5; pb.stringValue = "hi"
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" })
        var emissions = 0
        monitor.onNewItem = { _ in emissions += 1 }
        monitor.poll(now: Date())   // first read at count 5 -> emit
        monitor.poll(now: Date())   // unchanged -> no emit
        XCTAssertEqual(emissions, 1)
    }

    func testEmitsTextItemOnChange() {
        let pb = FakePasteboard()
        pb.changeCount = 1; pb.stringValue = "hello world"
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" })
        var captured: ClipboardItem?
        monitor.onNewItem = { captured = $0 }
        monitor.poll(now: Date())
        XCTAssertEqual(captured?.kind, .text)
        XCTAssertEqual(captured?.preview, "hello world")
    }

    func testConcealedNotEmitted() {
        let pb = FakePasteboard()
        pb.changeCount = 1; pb.stringValue = "secret"; pb.types = ["org.nspasteboard.ConcealedType"]
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" })
        var emissions = 0
        monitor.onNewItem = { _ in emissions += 1 }
        monitor.poll(now: Date())
        XCTAssertEqual(emissions, 0)
    }

    func testIdenticalImagesProduceEqualContentHash() {
        let pb = FakePasteboard()
        pb.imageBytes = Data([0x1, 0x2, 0x3, 0x4, 0x5])
        var blobCounter = 0
        // Each capture writes a fresh blob under a distinct filename, exactly like the real Store.
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in
            blobCounter += 1
            return "blob-\(blobCounter).png"
        })
        var hashes: [String] = []
        monitor.onNewItem = { hashes.append($0.contentHash) }

        pb.changeCount = 1; monitor.poll(now: Date())
        pb.changeCount = 2; monitor.poll(now: Date())   // same image content, fresh capture

        XCTAssertEqual(hashes.count, 2)
        XCTAssertEqual(hashes[0], hashes[1],
                       "identical image content must dedupe to the same hash, independent of the blob filename")
    }

    func testDifferentImagesProduceDifferentContentHash() {
        let pb = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "blob.png" })
        var hashes: [String] = []
        monitor.onNewItem = { hashes.append($0.contentHash) }

        pb.imageBytes = Data([0x1, 0x2, 0x3]); pb.changeCount = 1; monitor.poll(now: Date())
        pb.imageBytes = Data([0x9, 0x8, 0x7]); pb.changeCount = 2; monitor.poll(now: Date())

        XCTAssertEqual(hashes.count, 2)
        XCTAssertNotEqual(hashes[0], hashes[1],
                          "different image content must hash differently even when the blob filename is reused")
    }
}
