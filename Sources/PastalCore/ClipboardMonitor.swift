import Foundation

public final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let writeImageBlob: (Data) throws -> String
    private var lastChangeCount: Int?

    public var onNewItem: ((ClipboardItem) -> Void)?

    public init(pasteboard: PasteboardReading, writeImageBlob: @escaping (Data) throws -> String) {
        self.pasteboard = pasteboard
        self.writeImageBlob = writeImageBlob
    }

    public func poll(now: Date) {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard PrivacyFilter.shouldStore(pasteboardTypes: pasteboard.types) else { return }
        guard let item = buildItem(now: now) else { return }
        onNewItem?(item)
    }

    private func buildItem(now: Date) -> ClipboardItem? {
        if let data = pasteboard.imageData() {
            guard let path = try? writeImageBlob(data) else { return nil }
            return ClipboardItem(kind: .image, preview: "Image", text: nil,
                                 imagePath: path, filePaths: [], createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .image, text: nil, imagePath: path, filePaths: []))
        }
        let files = pasteboard.fileURLs()
        if !files.isEmpty {
            let preview = files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return ClipboardItem(kind: .file, preview: preview, text: nil,
                                 imagePath: nil, filePaths: files, createdAt: now, pinned: false,
                                 contentHash: ClipboardItem.contentHash(kind: .file, text: nil, imagePath: nil, filePaths: files))
        }
        guard let s = pasteboard.string(), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let preview = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return ClipboardItem(kind: .text, preview: preview, text: s,
                             imagePath: nil, filePaths: [], createdAt: now, pinned: false,
                             contentHash: ClipboardItem.contentHash(kind: .text, text: s, imagePath: nil, filePaths: []))
    }
}
