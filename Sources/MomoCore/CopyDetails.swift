import Foundation

/// What a row's hover card shows: the content, then what Momo knows about how it was copied.
/// Facts it doesn't know (for items recorded before it tracked them) are left out.
public enum CopyDetails {
    public enum Fact: Equatable {
        case app(SourceApp)
        case firstCopied(Date)
        case lastCopied(Date)
        case copies(Int)
    }

    /// A text clip's text (trimmed, cut to `contentLimit` characters and `maxLines` lines), a file
    /// clip's paths, or "Image" — short enough that the card stays small.
    public static func content(of item: ClipboardItem) -> String {
        switch item.kind {
        case .text, .richText:
            let text = PreviewText.excerpt(item.text ?? item.preview, limit: contentLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            guard lines.count > maxLines else { return text }
            return lines.prefix(maxLines).joined(separator: "\n") + "…"
        case .file:
            var lines = item.filePaths.prefix(maxFiles).map { ($0 as NSString).abbreviatingWithTildeInPath }
            if item.filePaths.count > maxFiles { lines.append("and \(item.filePaths.count - maxFiles) more") }
            return lines.joined(separator: "\n")
        case .image:
            return "Image"
        }
    }

    public static func facts(of item: ClipboardItem) -> [Fact] {
        var facts: [Fact] = []
        if let app = item.sourceApp { facts.append(.app(app)) }
        if let first = item.firstCopiedAt { facts.append(.firstCopied(first)) }
        facts.append(.lastCopied(item.createdAt))
        if let count = item.copyCount { facts.append(.copies(count)) }
        return facts
    }

    static let contentLimit = 500
    static let maxLines = 8
    static let maxFiles = 5
}
