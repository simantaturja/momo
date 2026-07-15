import XCTest
@testable import PastalCore

private final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var types: Set<String> = ["public.utf8-plain-text"]
    var stringValue: String?
    func string() -> String? { stringValue }
    func imageData() -> Data? { nil }
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
}
