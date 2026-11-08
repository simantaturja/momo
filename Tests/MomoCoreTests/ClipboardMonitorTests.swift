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
        var frontmost: SourceApp? = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { frontmost })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch: nothing on the clipboard yet

        pb.stringValue = "hello"; pb.changeCount = 1; monitor.poll(now: Date())
        frontmost = SourceApp(name: "Finder", bundleID: "com.apple.finder")
        pb.fileURLValues = ["/tmp/a.txt"]; pb.changeCount = 2; monitor.poll(now: Date())
        frontmost = nil   // unknown, or Momo itself
        pb.fileURLValues = []; pb.imageBytes = Data([0x1]); pb.changeCount = 3; monitor.poll(now: Date())

        XCTAssertEqual(captured.map(\.kind), [.text, .file, .image])
        XCTAssertEqual(captured.map(\.sourceApp), [SourceApp(name: "Safari", bundleID: "com.apple.Safari"),
                                                    SourceApp(name: "Finder", bundleID: "com.apple.finder"), nil])
    }

    func testCopyAlreadyOnTheClipboardAtLaunchHasNoKnownSourceOrHistory() {
        // It was copied while Momo wasn't watching: the app in front at launch didn't make it,
        // and when it was copied, or whether it's a new copy at all, is unknown.
        let pb = FakePasteboard()
        pb.stringValue = "from before launch"; pb.changeCount = 7
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { SourceApp(name: "Safari") })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        let launch = Date(timeIntervalSince1970: 100), later = Date(timeIntervalSince1970: 200)
        monitor.poll(now: launch)
        pb.stringValue = "seen"; pb.changeCount = 8; monitor.poll(now: later)
        XCTAssertEqual(captured.map(\.sourceApp?.name), [nil, "Safari"])
        XCTAssertEqual(captured.map(\.firstCopiedAt), [nil, later])
        XCTAssertEqual(captured.map(\.copyCount), [nil, 1])
    }

    func testMomosOwnCopiesAreCreditedToNoApp() {
        // A re-copy or "Copy N" from the panel is seen while focus goes back to another app.
        let pb = FakePasteboard()
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { SourceApp(name: "Safari") })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch
        pb.stringValue = "a\nb"; pb.changeCount = 1
        pb.types = ["public.utf8-plain-text", ClipboardMonitor.ownCopyType]
        let now = Date(timeIntervalSince1970: 100)
        monitor.poll(now: now)
        XCTAssertEqual(captured.map(\.text), ["a\nb"])   // still captured
        XCTAssertEqual(captured.map(\.sourceApp), [nil])
        XCTAssertEqual(captured.map(\.firstCopiedAt), [now])   // and still a copy Momo saw
        XCTAssertEqual(captured.map(\.copyCount), [1])
    }

    func testSourceIsTheAppInFrontWhenTheCopyIsSeen() {
        // Saving a big image takes a while; switching apps meanwhile mustn't change the credit.
        let pb = FakePasteboard()
        var frontmost = "Preview"
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in
            frontmost = "Slack"
            return "x.png"
        }, sourceApp: { SourceApp(name: frontmost) })
        var captured: [ClipboardItem] = []
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch
        pb.imageBytes = Data([0x1]); pb.changeCount = 1; monitor.poll(now: Date())
        XCTAssertEqual(captured.map(\.sourceApp?.name), ["Preview"])
    }

    // MARK: Capture rules

    /// A monitor that has already seen the launch clip, so the next change is a copy it saw.
    private func watching(_ pb: FakePasteboard, rules: CaptureRules = CaptureRules(),
                          source: SourceApp? = SourceApp(name: "Safari", bundleID: "com.apple.Safari"),
                          blobs: @escaping (Data) throws -> String = { _ in "x.png" },
                          isPaused: @escaping () -> Bool = { false },
                          consumeIgnoreNext: @escaping () -> Bool = { false }) -> (ClipboardMonitor, () -> [ClipboardItem]) {
        var captured: [ClipboardItem] = []
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: blobs, sourceApp: { source },
                                       rules: { rules }, isPaused: isPaused, consumeIgnoreNext: consumeIgnoreNext)
        monitor.onNewItem = { captured.append($0) }
        monitor.poll(now: Date())   // launch: nothing on the clipboard
        return (monitor, { captured })
    }

    func testCopiesMadeWhilePausedAreNeverCaptured() {
        let pb = FakePasteboard()
        var paused = true
        var asked = 0
        let (monitor, captured) = watching(pb, isPaused: { paused }, consumeIgnoreNext: { asked += 1; return false })
        pb.stringValue = "while paused"; pb.changeCount = 1; monitor.poll(now: Date())
        paused = false
        monitor.poll(now: Date())   // unpausing doesn't pick up the copy made while paused
        XCTAssertEqual(captured().map(\.text), [])
        XCTAssertEqual(asked, 0, "a paused copy doesn't use up ignore-next")
        pb.stringValue = "after"; pb.changeCount = 2; monitor.poll(now: Date())
        XCTAssertEqual(captured().map(\.text), ["after"])
    }

    func testIgnoreNextDropsOnlyTheNextSeenCopyThatIsNotMomos() {
        let pb = FakePasteboard()
        pb.stringValue = "launch clip"; pb.changeCount = 1
        var ignoreNext = true
        var asked = 0
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       consumeIgnoreNext: {
                                           asked += 1
                                           defer { ignoreNext = false }   // read-and-clear, as Settings does
                                           return ignoreNext
                                       })
        var captured: [String?] = []
        monitor.onNewItem = { captured.append($0.text) }
        monitor.poll(now: Date())   // the launch clip: not a copy Momo saw, so not asked
        pb.stringValue = "own"; pb.types = ["public.utf8-plain-text", ClipboardMonitor.ownCopyType]
        pb.changeCount = 2; monitor.poll(now: Date())   // Momo's own copy: not asked either
        XCTAssertEqual(asked, 0)
        pb.types = ["public.utf8-plain-text"]
        pb.stringValue = "ignored"; pb.changeCount = 3; monitor.poll(now: Date())
        pb.stringValue = "kept"; pb.changeCount = 4; monitor.poll(now: Date())
        XCTAssertEqual(captured, ["launch clip", "own", "kept"])
        XCTAssertEqual(asked, 2)
    }

    func testIgnoredPasteboardTypeDropsTheCopy() {
        let pb = FakePasteboard()
        let (monitor, captured) = watching(pb, rules: CaptureRules(ignoredTypes: ["com.example.secret"]))
        pb.stringValue = "a"; pb.types = ["public.utf8-plain-text", "com.example.secret"]
        pb.changeCount = 1; monitor.poll(now: Date())
        pb.stringValue = "b"; pb.types = ["public.utf8-plain-text"]
        pb.changeCount = 2; monitor.poll(now: Date())
        XCTAssertEqual(captured().map(\.text), ["b"])
    }

    func testCopiesFromAnIgnoredAppAreDroppedButMomosOwnAreKept() {
        let pb = FakePasteboard()
        let (monitor, captured) = watching(pb, rules: CaptureRules(ignoredBundleIDs: ["com.apple.Safari"]))
        pb.stringValue = "from Safari"; pb.changeCount = 1; monitor.poll(now: Date())
        pb.stringValue = "own"; pb.types = ["public.utf8-plain-text", ClipboardMonitor.ownCopyType]
        pb.changeCount = 2; monitor.poll(now: Date())   // Safari is in front, but Momo made this copy
        XCTAssertEqual(captured().map(\.text), ["own"])
    }

    func testOnlyListedAppsKeepsCopiesFromListedAppsAndMomoOnly() {
        let rules = CaptureRules(ignoredBundleIDs: ["com.apple.Notes"], onlyListedApps: true)
        let pb = FakePasteboard()
        pb.stringValue = "launch clip"; pb.changeCount = 1   // unknown source: dropped in this mode
        var front: SourceApp? = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { front }, rules: { rules })
        var captured: [String?] = []
        monitor.onNewItem = { captured.append($0.text) }
        monitor.poll(now: Date())
        pb.stringValue = "from Safari"; pb.changeCount = 2; monitor.poll(now: Date())
        front = SourceApp(name: "Notes", bundleID: "com.apple.Notes")
        pb.stringValue = "from Notes"; pb.changeCount = 3; monitor.poll(now: Date())
        front = SourceApp(name: "Mystery")   // no bundle id: unknown
        pb.stringValue = "from Mystery"; pb.changeCount = 4; monitor.poll(now: Date())
        pb.stringValue = "own"; pb.types = ["public.utf8-plain-text", ClipboardMonitor.ownCopyType]
        pb.changeCount = 5; monitor.poll(now: Date())
        XCTAssertEqual(captured, ["from Notes", "own"])
    }

    func testADisabledKindDropsTheCopyRatherThanFallingBack() {
        // Finder puts the file name on the pasteboard as text too; with files off, it isn't saved as text.
        let pb = FakePasteboard()
        let (monitor, captured) = watching(pb, rules: CaptureRules(saveFiles: false))
        pb.fileURLValues = ["/tmp/a.txt"]; pb.stringValue = "a.txt"; pb.changeCount = 1; monitor.poll(now: Date())
        pb.fileURLValues = []; pb.stringValue = "plain"; pb.changeCount = 2; monitor.poll(now: Date())
        XCTAssertEqual(captured().map(\.text), ["plain"])

        let textOff = FakePasteboard()
        let (textMonitor, textCaptured) = watching(textOff, rules: CaptureRules(saveText: false))
        textOff.stringValue = "plain"; textOff.changeCount = 1; textMonitor.poll(now: Date())
        textOff.fileURLValues = ["/tmp/a.txt"]; textOff.changeCount = 2; textMonitor.poll(now: Date())
        XCTAssertEqual(textCaptured().map(\.kind), [.file])
    }

    func testImagesOffDropsTheCopyWithoutWritingABlob() {
        let pb = FakePasteboard()
        var blobsWritten = 0
        let (monitor, captured) = watching(pb, rules: CaptureRules(saveImages: false),
                                           blobs: { _ in blobsWritten += 1; return "x.png" })
        pb.imageBytes = Data([0x1]); pb.stringValue = "alt text"; pb.changeCount = 1; monitor.poll(now: Date())
        XCTAssertEqual(captured().count, 0, "not saved as its text either")
        XCTAssertEqual(blobsWritten, 0, "a dropped copy must not leave a blob behind")
    }

    func testDroppedCopiesNeverWriteABlob() {
        // Every rule that drops an image copy is checked before its blob is written.
        let scenarios: [(name: String, rules: CaptureRules, paused: Bool, ignoreNext: Bool)] = [
            ("ignored app", CaptureRules(ignoredBundleIDs: ["com.apple.Safari"]), false, false),
            ("ignored type", CaptureRules(ignoredTypes: ["public.png"]), false, false),
            ("paused", CaptureRules(), true, false),
            ("ignore next", CaptureRules(), false, true),
        ]
        for scenario in scenarios {
            let pb = FakePasteboard()
            var blobsWritten = 0
            let (monitor, captured) = watching(pb, rules: scenario.rules,
                                               blobs: { _ in blobsWritten += 1; return "x.png" },
                                               isPaused: { scenario.paused },
                                               consumeIgnoreNext: { scenario.ignoreNext })
            pb.types = ["public.png"]
            pb.imageBytes = Data([0x1]); pb.changeCount = 1; monitor.poll(now: Date())
            XCTAssertEqual(captured().count, 0, scenario.name)
            XCTAssertEqual(blobsWritten, 0, scenario.name)
        }
    }

    func testIgnoreNextIsNotUsedUpByACopyThatIsDroppedAnyway() {
        // The skip is for the next copy that would be saved: one a rule drops doesn't count.
        let pb = FakePasteboard()
        var ignoreNext = true
        let rules = CaptureRules(saveFiles: false, ignoredBundleIDs: ["com.apple.Safari"],
                                 ignoredTypes: ["com.example.secret"])
        var front: SourceApp? = SourceApp(name: "Notes", bundleID: "com.apple.Notes")
        let monitor = ClipboardMonitor(pasteboard: pb, writeImageBlob: { _ in "x.png" },
                                       sourceApp: { front }, rules: { rules },
                                       consumeIgnoreNext: {
                                           defer { ignoreNext = false }
                                           return ignoreNext
                                       })
        var captured: [String?] = []
        monitor.onNewItem = { captured.append($0.text) }
        monitor.poll(now: Date())   // launch
        pb.types = ["public.utf8-plain-text", "org.nspasteboard.TransientType"]
        pb.stringValue = "transient"; pb.changeCount = 1; monitor.poll(now: Date())
        pb.types = ["public.utf8-plain-text", "com.example.secret"]
        pb.stringValue = "ignored type"; pb.changeCount = 2; monitor.poll(now: Date())
        pb.types = ["public.utf8-plain-text"]
        front = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
        pb.stringValue = "ignored app"; pb.changeCount = 3; monitor.poll(now: Date())
        front = SourceApp(name: "Notes", bundleID: "com.apple.Notes")
        pb.fileURLValues = ["/tmp/a.txt"]; pb.changeCount = 4; monitor.poll(now: Date())   // files off
        pb.fileURLValues = []
        pb.stringValue = "skipped"; pb.changeCount = 5; monitor.poll(now: Date())
        pb.stringValue = "kept"; pb.changeCount = 6; monitor.poll(now: Date())
        XCTAssertEqual(captured, ["kept"])
    }

    func testTextMatchingAnIgnoredPatternIsDropped() {
        let pb = FakePasteboard()
        // An invalid pattern and an empty one (a freshly added row) are skipped, not fatal or match-all.
        let rules = CaptureRules(ignoredPatterns: ["(unclosed", "", "^sk-[A-Za-z0-9]+$", "secret"])
        let (monitor, captured) = watching(pb, rules: rules)
        let longPrefix = String(repeating: "x", count: 300)   // past the 200-character preview
        for (i, text) in ["sk-abc123", "hello", longPrefix + " my secret", "sk-abc 123"].enumerated() {
            pb.stringValue = text; pb.changeCount = i + 1; monitor.poll(now: Date())
        }
        XCTAssertEqual(captured().map(\.text), ["hello", "sk-abc 123"])
    }

    func testPatternsDoNotApplyToFilesOrImages() {
        let pb = FakePasteboard()
        let (monitor, captured) = watching(pb, rules: CaptureRules(ignoredPatterns: ["a"]))
        pb.fileURLValues = ["/tmp/a.txt"]; pb.changeCount = 1; monitor.poll(now: Date())
        XCTAssertEqual(captured().map(\.kind), [.file])
    }
}
