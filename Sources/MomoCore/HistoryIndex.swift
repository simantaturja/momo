import Foundation

/// One history item as the list draws it. `line` and `flavor` are derived once, when the item
/// enters the index — never per keystroke. `matchedPositions` are the Character offsets in
/// `line` that the current query matched (empty for an empty query).
public struct HistoryRow: Equatable, Sendable {
    public let item: ClipboardItem
    public let line: String
    public let flavor: ContentFlavor
    public let matchedPositions: [Int]
}

/// The scope chips above the list. `.files(extension: nil)` is any file item.
public enum HistoryScope: Equatable, Sendable {
    case all, text, links, images, files(extension: String?), pinned
}

public final class HistoryIndex {
    private var rows: [HistoryRow] = []

    public init() {}

    public func replaceAll(_ items: [ClipboardItem]) {
        rows = items.map(Self.row)
    }

    public func prepend(_ item: ClipboardItem) {
        var item = item
        if let existing = rows.first(where: { $0.item.contentHash == item.contentHash })?.item {
            item = ClipboardItem(id: existing.id, kind: item.kind, preview: item.preview,
                                  text: item.text, imagePath: existing.imagePath, filePaths: item.filePaths,
                                  createdAt: item.createdAt, pinned: existing.pinned, contentHash: item.contentHash,
                                  sourceApp: existing.sourceApp)
        }
        rows.removeAll { $0.item.contentHash == item.contentHash }
        rows.insert(Self.row(item), at: 0)
    }

    /// Fuzzy-matches against each row's `line` (what's drawn), so highlights line up.
    public func search(_ query: String, scope: HistoryScope = .all) -> [HistoryRow] {
        let candidates = rows.filter { $0.isIn(scope) }
        guard !query.isEmpty else { return candidates }
        let scored: [(row: HistoryRow, score: Int)] = candidates.compactMap { row in
            guard let match = fuzzyMatch(query: query, candidate: row.line) else { return nil }
            return (HistoryRow(item: row.item, line: row.line, flavor: row.flavor,
                               matchedPositions: match.positions), match.score)
        }
        return scored.sorted { a, b in
            if a.row.item.pinned != b.row.item.pinned { return a.row.item.pinned }
            if a.score != b.score { return a.score > b.score }
            return a.row.item.createdAt > b.row.item.createdAt
        }.map(\.row)
    }

    public func distinctFileExtensions() -> [String] {
        let extensions = rows.map(\.item)
            .filter { $0.kind == .file }
            .flatMap { $0.filePaths }
            .map { ($0 as NSString).pathExtension.lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(extensions)).sorted()
    }

    private static func row(_ item: ClipboardItem) -> HistoryRow {
        HistoryRow(item: item, line: PreviewText.singleLine(item.preview), flavor: flavor(of: item),
                   matchedPositions: [])
    }

    /// Detected on the preview, which is only the first 200 characters, so a link is confirmed
    /// against the full text: Open Link and the preview use all of it.
    private static func flavor(of item: ClipboardItem) -> ContentFlavor {
        guard item.kind == .text else { return .plain }
        let flavor = ContentFlavor.detect(item.preview)
        guard flavor == .link, let text = item.text else { return flavor }
        return ContentFlavor.isLink(text) ? .link : .plain
    }
}

private extension HistoryRow {
    func isIn(_ scope: HistoryScope) -> Bool {
        switch scope {
        case .all: return true
        case .text: return item.kind == .text
        case .links: return flavor == .link
        case .images: return item.kind == .image
        case .files(let fileExtension): return item.matches(kind: .file, fileExtension: fileExtension)
        case .pinned: return item.pinned
        }
    }
}
