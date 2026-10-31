import Foundation

public final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let writeImageBlob: (Data) throws -> String
    private let allowsConcealed: () -> Bool
    private let sourceApp: () -> String?
    private var lastChangeCount: Int?

    public var onNewItem: ((ClipboardItem) -> Void)?

    /// `allowsConcealed` is asked on every capture, so a settings change applies to the next copy.
    /// `sourceApp` is asked once per captured copy for the name of the app it came from.
    public init(pasteboard: PasteboardReading, writeImageBlob: @escaping (Data) throws -> String,
                allowsConcealed: @escaping () -> Bool = { false },
                sourceApp: @escaping () -> String? = { nil }) {
        self.pasteboard = pasteboard
        self.writeImageBlob = writeImageBlob
        self.allowsConcealed = allowsConcealed
        self.sourceApp = sourceApp
    }

    public func poll(now: Date) {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard PrivacyFilter.shouldStore(pasteboardTypes: pasteboard.types,
                                        allowConcealed: allowsConcealed()) else { return }
        guard var item = buildItem(now: now) else { return }
        item.sourceApp = sourceApp()
        onNewItem?(item)
    }

    private func buildItem(now: Date) -> ClipboardItem? {
        let files = pasteboard.fileURLs()
        if !files.isEmpty {
            let preview = files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return ClipboardItem(kind: .file, preview: preview, text: nil,
                                 imagePath: nil, filePaths: files, createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .file, text: nil, imageHash: nil, filePaths: files))
        }
        if let data = pasteboard.imageData() {
            // Identity is the image bytes; the blob filename is incidental and must not enter the hash.
            let imageHash = ClipboardItem.imageHash(data)
            guard let path = try? writeImageBlob(data) else { return nil }
            return ClipboardItem(kind: .image, preview: "Image", text: nil,
                                 imagePath: path, filePaths: [], createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .image, text: nil, imageHash: imageHash, filePaths: []))
        }
        guard let s = pasteboard.string(), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let preview = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return ClipboardItem(kind: .text, preview: preview, text: s,
                             imagePath: nil, filePaths: [], createdAt: now, pinned: false,
                             contentHash: ClipboardItem.contentHash(kind: .text, text: s, imageHash: nil, filePaths: []))
    }
}
