import Foundation

public enum ItemKind: String, Codable, Sendable {
    case text, richText, image, file
}

/// The app a copy came from: its display name and, to find its icon, its bundle identifier.
public struct SourceApp: Equatable, Sendable {
    public var name: String
    public var bundleID: String?

    public init(name: String, bundleID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: ItemKind
    public var preview: String
    public var text: String?
    public var imagePath: String?
    public var filePaths: [String]
    public var createdAt: Date
    public var pinned: Bool
    public var contentHash: String
    /// The app the content was first copied from (the frontmost app when it was seen).
    /// This and the copy history below are nil when unknown: for items recorded before Momo
    /// tracked them, and for the clip found on the clipboard at launch, whose copy Momo didn't see.
    /// `createdAt` is the last copy.
    public var sourceApp: SourceApp?
    public var firstCopiedAt: Date?
    /// How many times the content has been copied.
    public var copyCount: Int?

    public init(id: UUID = UUID(), kind: ItemKind, preview: String,
                text: String?, imagePath: String?, filePaths: [String],
                createdAt: Date, pinned: Bool, contentHash: String, sourceApp: SourceApp? = nil,
                firstCopiedAt: Date? = nil, copyCount: Int? = nil) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.text = text
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = contentHash
        self.sourceApp = sourceApp
        self.firstCopiedAt = firstCopiedAt
        self.copyCount = copyCount
    }

    /// True if this item passes the given kind/extension filter. `kind == nil` matches
    /// anything. A non-nil `fileExtension` never matches an item whose kind isn't `.file`.
    public func matches(kind: ItemKind?, fileExtension: String?) -> Bool {
        guard let kind else { return true }
        guard self.kind == kind else { return false }
        guard kind == .file else {
            // If a file extension is specified but this item is not a file, reject it
            return fileExtension == nil
        }
        guard let fileExtension else { return true }
        return filePaths.contains { (($0 as NSString).pathExtension).caseInsensitiveCompare(fileExtension) == .orderedSame }
    }

    /// Deterministic hash of the payload, used as the dedupe key.
    /// For images, pass `imageHash` (a digest of the image bytes, via `imageHash(_:)`) —
    /// never the storage path, which is a fresh UUID on every capture and would defeat dedupe.
    public static func contentHash(kind: ItemKind, text: String?,
                                   imageHash: String?, filePaths: [String]) -> String {
        let canonical = "\(kind.rawValue)|\(text ?? "")|\(imageHash ?? "")|\(filePaths.joined(separator: ","))"
        return djb2Hex(canonical.utf8)
    }

    /// Content-identity digest of raw image bytes, so re-copying the same image dedupes.
    public static func imageHash(_ data: Data) -> String {
        djb2Hex(data)
    }

    private static func djb2Hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var hash: UInt64 = 5381
        for byte in bytes {
            hash = (hash &* 33) ^ UInt64(byte)   // djb2, deterministic
        }
        return String(hash, radix: 16)
    }
}
