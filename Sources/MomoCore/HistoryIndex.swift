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

/// What the list is ordered by, newest / most first.
public enum HistorySort: String, Sendable {
    case lastCopy, firstCopy, copyCount
}

public enum PinPlacement: String, Sendable {
    case top, bottom
}

public final class HistoryIndex {
    /// Kept in display order, so an empty query (every open) costs no sort: rows are ordered when
    /// they change or the order does, never per keystroke.
    private var rows: [HistoryRow] = []

    public var sort = HistorySort.lastCopy { didSet { rows.sort(by: precedes) } }
    public var pinPlacement = PinPlacement.top { didSet { rows.sort(by: precedes) } }

    public init() {}

    public func replaceAll(_ items: [ClipboardItem]) {
        rows = items.map(Self.row).sorted(by: precedes)
    }

    public func prepend(_ item: ClipboardItem) {
        var item = item
        if let existing = rows.first(where: { $0.item.contentHash == item.contentHash })?.item {
            guard let added = item.copyCount else { return }   // unseen (the launch clip): as Store.upsert
            item = ClipboardItem(id: existing.id, kind: item.kind, preview: item.preview,
                                  text: item.text, imagePath: existing.imagePath, filePaths: item.filePaths,
                                  createdAt: item.createdAt, pinned: existing.pinned, contentHash: item.contentHash,
                                  sourceApp: existing.sourceApp, firstCopiedAt: existing.firstCopiedAt,
                                  copyCount: existing.copyCount.map { $0 + added }, title: existing.title)
        }
        rows.removeAll { $0.item.contentHash == item.contentHash }
        let row = Self.row(item)
        let position = rows.firstIndex { precedes(row, $0) } ?? rows.count   // keeps the rows in order
        rows.insert(row, at: position)
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
            if let first = pinFirst(a.row.item, b.row.item) { return first }
            if a.score != b.score { return a.score > b.score }
            return a.row.item.createdAt > b.row.item.createdAt
        }.map(\.row)
    }

    /// Whether `a` goes before `b` in the list: pins per their placement, then the sort key, then the last copy.
    private func precedes(_ a: HistoryRow, _ b: HistoryRow) -> Bool {
        if let first = pinFirst(a.item, b.item) { return first }
        let (keyA, keyB) = (sortKey(a.item), sortKey(b.item))
        if keyA != keyB { return keyA > keyB }
        return a.item.createdAt > b.item.createdAt
    }

    /// Whether `a` goes first because of pinning; nil when both or neither are pinned.
    private func pinFirst(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool? {
        guard a.pinned != b.pinned else { return nil }
        return a.pinned == (pinPlacement == .top)
    }

    private func sortKey(_ item: ClipboardItem) -> Double {
        switch sort {
        case .lastCopy: return item.createdAt.timeIntervalSince1970
        case .firstCopy: return (item.firstCopiedAt ?? item.createdAt).timeIntervalSince1970
        case .copyCount: return Double(item.copyCount ?? 1)
        }
    }

    public func distinctFileExtensions() -> [String] {
        let extensions = rows.map(\.item)
            .filter { $0.kind == .file }
            .flatMap { $0.filePaths }
            .map { ($0 as NSString).pathExtension.lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(extensions)).sorted()
    }

    /// A titled item shows (and is searched by) its title instead of its preview.
    private static func row(_ item: ClipboardItem) -> HistoryRow {
        let title = PreviewText.singleLine(item.title ?? "")
        return HistoryRow(item: item, line: title.isEmpty ? PreviewText.singleLine(item.preview) : title,
                          flavor: flavor(of: item), matchedPositions: [])
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
