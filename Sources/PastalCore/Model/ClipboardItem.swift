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

    /// Deterministic hash of the payload, used as the dedupe key.
    public static func contentHash(kind: ItemKind, text: String?,
                                   imagePath: String?, filePaths: [String]) -> String {
        let canonical = "\(kind.rawValue)|\(text ?? "")|\(imagePath ?? "")|\(filePaths.joined(separator: ","))"
        var hash: UInt64 = 5381
        for byte in canonical.utf8 {
            hash = (hash &* 33) ^ UInt64(byte)   // djb2, deterministic
        }
        return String(hash, radix: 16)
    }
}
