import XCTest
@testable import MomoCore

private final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var types: Set<String> = ["public.utf8-plain-text"]
    var stringValue: String?
    var imageBytes: Data?
    var fileURLValues: [String] = []
    func string() -> String? { stringValue }
    func imageData() -> Data? { imageBytes }
    func fileURLs() -> [String] { fileURLValues }
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

    func testConcealedEmittedWhenAllowed() {
        let pb = FakePasteboard()
        pb.changeCount = 1; pb.stringValue = "secret"; pb.types = ["org.nspasteboard.ConcealedType"]
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       allowsConcealed: { true })
        var captured: ClipboardItem?
        monitor.onNewItem = { captured = $0 }
        monitor.poll(now: Date())
        XCTAssertEqual(captured?.text, "secret")
    }

    func testTransientNotEmittedEvenWhenConcealedAllowed() {
        // The opt-in covers passwords only; a pasteboard also marked transient stays out.
        let pb = FakePasteboard()
        pb.changeCount = 1; pb.stringValue = "secret"
        pb.types = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       allowsConcealed: { true })
        var emissions = 0
        monitor.onNewItem = { _ in emissions += 1 }
        monitor.poll(now: Date())
        XCTAssertEqual(emissions, 0)
    }

    func testConcealedSettingTakesEffectWithoutRestart() {
        // The setting is read on every capture, so flipping it applies to the very next copy.
        let pb = FakePasteboard()
        pb.types = ["org.nspasteboard.ConcealedType"]
        var allowed = false
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       allowsConcealed: { allowed })
        var texts: [String?] = []
        monitor.onNewItem = { texts.append($0.text) }

        pb.stringValue = "first"; pb.changeCount = 1; monitor.poll(now: Date())    // off -> dropped
        allowed = true
        pb.stringValue = "second"; pb.changeCount = 2; monitor.poll(now: Date())   // on -> kept
        allowed = false
        pb.stringValue = "third"; pb.changeCount = 3; monitor.poll(now: Date())    // off again -> dropped

        XCTAssertEqual(texts, ["second"])
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

    func testFileWithImagePreviewCapturedAsFileNotImage() {
        // Finder puts a bitmap preview rep on the pasteboard alongside the file URL for some
        // file types (e.g. PDFs with a QuickLook thumbnail). File identity must win.
        let pb = FakePasteboard()
        pb.changeCount = 1
        pb.fileURLValues = ["/tmp/doc.pdf"]
        pb.imageBytes = Data([0x1, 0x2, 0x3])
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "blob.png" })
        var captured: ClipboardItem?
        monitor.onNewItem = { captured = $0 }
        monitor.poll(now: Date())
        XCTAssertEqual(captured?.kind, .file)
        XCTAssertEqual(captured?.filePaths, ["/tmp/doc.pdf"])
    }

    func testRecordsTheSourceAppOfEachCopy() {
        // Asked per capture, for every kind: the app in front when this copy was seen.
        let pb = FakePasteboard()
        var frontmost: String? = "Safari"
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { frontmost })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch: nothing on the clipboard yet

        pb.stringValue = "hello"; pb.changeCount = 1; monitor.poll(now: Date())
        frontmost = "Finder"
        pb.fileURLValues = ["/tmp/a.txt"]; pb.changeCount = 2; monitor.poll(now: Date())
        frontmost = nil   // unknown, or Momo itself
        pb.fileURLValues = []; pb.imageBytes = Data([0x1]); pb.changeCount = 3; monitor.poll(now: Date())

        XCTAssertEqual(captured.map(\.kind), [.text, .file, .image])
        XCTAssertEqual(captured.map(\.sourceApp), ["Safari", "Finder", nil])
    }

    func testCopyAlreadyOnTheClipboardAtLaunchIsCreditedToNoApp() {
        // It was copied while Momo wasn't watching; the app in front at launch didn't make it.
        let pb = FakePasteboard()
        pb.stringValue = "from before launch"; pb.changeCount = 7
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { "Safari" })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())
        pb.stringValue = "seen"; pb.changeCount = 8; monitor.poll(now: Date())
        XCTAssertEqual(captured.map(\.sourceApp), [nil, "Safari"])
    }

    func testMomosOwnCopiesAreCreditedToNoApp() {
        // A re-copy or "Copy N" from the panel is seen while focus goes back to another app.
        let pb = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { "Safari" })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch
        pb.stringValue = "a\nb"; pb.changeCount = 1
        pb.types = ["public.utf8-plain-text", ClipboardMonitor.ownCopyType]
        monitor.poll(now: Date())
        XCTAssertEqual(captured.map(\.text), ["a\nb"])   // still captured
        XCTAssertEqual(captured.map(\.sourceApp), [nil])
    }

    func testSourceIsTheAppInFrontWhenTheCopyIsSeen() {
        // Saving a big image takes a while; switching apps meanwhile mustn't change the credit.
        let pb = FakePasteboard()
        var frontmost = "Preview"
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in
            frontmost = "Slack"
            return "x.png"
        }, sourceApp: { frontmost })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch
        pb.imageBytes = Data([0x1]); pb.changeCount = 1; monitor.poll(now: Date())
        XCTAssertEqual(captured.map(\.sourceApp), ["Preview"])
    }
}
