import Foundation

public final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let writeImageBlob: (Data) throws -> String
    private let allowsConcealed: () -> Bool
    private let sourceApp: () -> SourceApp?
    private let rules: () -> CaptureRules
    private let isPaused: () -> Bool
    private let consumeIgnoreNext: () -> Bool
    private var lastChangeCount: Int?

    public var onNewItem: ((ClipboardItem) -> Void)?

    /// `allowsConcealed`, `rules` and `isPaused` are asked on every capture, so a settings change
    /// applies to the next copy. `sourceApp` names the app in front when a copy is seen;
    /// `consumeIgnoreNext` says whether to drop it (and clears the request). Neither is asked for
    /// the clip found at launch or for Momo's own copies.
    public init(pasteboard: PasteboardReading, writeImageBlob: @escaping (Data) throws -> String,
                allowsConcealed: @escaping () -> Bool = { false },
                sourceApp: @escaping () -> SourceApp? = { nil },
                rules: @escaping () -> CaptureRules = { CaptureRules() },
                isPaused: @escaping () -> Bool = { false },
                consumeIgnoreNext: @escaping () -> Bool = { false }) {
        self.pasteboard = pasteboard
        self.writeImageBlob = writeImageBlob
        self.allowsConcealed = allowsConcealed
        self.sourceApp = sourceApp
        self.rules = rules
        self.isPaused = isPaused
        self.consumeIgnoreNext = consumeIgnoreNext
    }

    /// Pasteboard type Momo adds to its own copies, which are seen while focus goes back to another app.
    public static let ownCopyType = "me.momo.app.own-copy"

    public func poll(now: Date) {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        let sawTheCopy = lastChangeCount != nil   // what's on the clipboard at launch was copied unseen
        lastChangeCount = count   // recorded even while paused, so those copies are never picked up later
        guard !isPaused() else { return }

        let types = pasteboard.types
        let own = types.contains(Self.ownCopyType)
        if sawTheCopy && !own && consumeIgnoreNext() { return }
        guard PrivacyFilter.shouldStore(pasteboardTypes: types,
                                        allowConcealed: allowsConcealed()) else { return }
        let rules = self.rules()
        guard rules.allows(types: types) else { return }
        // Asked before building the item: saving a big image takes a while, and the user may switch apps.
        let source = sawTheCopy && !own ? sourceApp() : nil
        guard own || rules.allows(sourceBundleID: source?.bundleID) else { return }
        guard var item = buildItem(now: now, rules: rules) else { return }
        item.sourceApp = source
        if sawTheCopy {   // Momo's own copies count too: it saw them happen
            item.firstCopiedAt = now
            item.copyCount = 1
        }
        onNewItem?(item)
    }

    /// The kind is files, else an image, else text; a kind the rules turn off drops the copy
    /// rather than falling back to another of its representations.
    private func buildItem(now: Date, rules: CaptureRules) -> ClipboardItem? {
        let files = pasteboard.fileURLs()
        if !files.isEmpty {
            guard rules.saveFiles else { return nil }
            let preview = files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return ClipboardItem(kind: .file, preview: preview, text: nil,
                                 imagePath: nil, filePaths: files, createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .file, text: nil, imageHash: nil, filePaths: files))
        }
        if let data = pasteboard.imageData() {
            guard rules.saveImages else { return nil }   // checked before the blob is written: no orphan
            // Identity is the image bytes; the blob filename is incidental and must not enter the hash.
            let imageHash = ClipboardItem.imageHash(data)
            guard let path = try? writeImageBlob(data) else { return nil }
            return ClipboardItem(kind: .image, preview: "Image", text: nil,
                                 imagePath: path, filePaths: [], createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .image, text: nil, imageHash: imageHash, filePaths: []))
        }
        guard rules.saveText, let s = pasteboard.string(),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rules.allows(text: s) else { return nil }
        return ClipboardItem(kind: .text, preview: ClipboardItem.textPreview(s), text: s,
                             imagePath: nil, filePaths: [], createdAt: now, pinned: false,
                             contentHash: ClipboardItem.contentHash(kind: .text, text: s, imageHash: nil, filePaths: []))
    }
}
