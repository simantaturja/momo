import Foundation

public enum ItemKind: String, Codable, Sendable {
    case text, richText, image, file
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

    public init(id: UUID = UUID(), kind: ItemKind, preview: String,
                text: String?, imagePath: String?, filePaths: [String],
                createdAt: Date, pinned: Bool, contentHash: String) {
        self.id = id
        self.kind = kind
        self.preview = preview
        self.text = text
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.createdAt = createdAt
        self.pinned = pinned
        self.contentHash = contentHash
    }

    /// True if this item passes the given kind/extension filter. `kind == nil` matches
    /// anything; `fileExtension` only constrains `.file`-kind items and is ignored otherwise.
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
