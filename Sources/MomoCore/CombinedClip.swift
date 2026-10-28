import Foundation

/// The payload for copying one or more history items in a single go: every text item joined
/// by newlines (in the order given), every file path (merged, duplicates dropped) and every
/// image blob. The shell writes whatever is non-empty to the pasteboard.
public struct CombinedClip {
    public let text: String?
    public let filePaths: [String]
    public let imagePaths: [String]

    public init(_ items: [ClipboardItem]) {
        var texts: [String] = []
        var files: [String] = []
        var images: [String] = []
        for item in items {
            switch item.kind {
            case .text, .richText:
                if let t = item.text { texts.append(t) }
            case .image:
                if let p = item.imagePath { images.append(p) }
            case .file:
                for p in item.filePaths where !files.contains(p) { files.append(p) }
            }
        }
        text = texts.isEmpty ? nil : texts.joined(separator: "\n")
        filePaths = files
        imagePaths = images
    }
}
