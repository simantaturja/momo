import Foundation

/// The payload for copying one or more history items in a single go: every text item joined
/// by newlines (in the order given), every file path (merged, duplicates dropped) and every
/// image blob. The shell writes whatever is non-empty to the pasteboard.
public struct CombinedClip {
    /// Every text item's text, in the order given.
    public let texts: [String]
    public let filePaths: [String]
    public let imagePaths: [String]

    /// `texts` joined by newlines, or nil if there are none. Joined on demand, so the preview
    /// can show an excerpt without building the full copy.
    public var text: String? { texts.isEmpty ? nil : texts.joined(separator: "\n") }

    public init(_ items: [ClipboardItem]) {
        var texts: [String] = []
        var files: [String] = []
        var seen = Set<String>()   // O(1) dedupe; a Finder copy can hold thousands of paths
        var images: [String] = []
        for item in items {
            switch item.kind {
            case .text, .richText:
                if let t = item.text { texts.append(t) }
            case .image:
                if let p = item.imagePath { images.append(p) }
            case .file:
                for p in item.filePaths where seen.insert(p).inserted { files.append(p) }
            }
        }
        self.texts = texts
        filePaths = files
        imagePaths = images
    }
}
