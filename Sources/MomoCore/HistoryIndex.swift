import Foundation

public final class HistoryIndex {
    private var items: [ClipboardItem] = []

    public init() {}

    public func replaceAll(_ items: [ClipboardItem]) {
        self.items = items
    }

    public func prepend(_ item: ClipboardItem) {
        var item = item
        if let existing = items.first(where: { $0.contentHash == item.contentHash }) {
            item = ClipboardItem(id: existing.id, kind: item.kind, preview: item.preview,
                                  text: item.text, imagePath: item.imagePath, filePaths: item.filePaths,
                                  createdAt: item.createdAt, pinned: item.pinned, contentHash: item.contentHash)
        }
        items.removeAll { $0.contentHash == item.contentHash }
        items.insert(item, at: 0)
    }

    public func search(_ query: String, kind: ItemKind? = nil, fileExtension: String? = nil) -> [ClipboardItem] {
        let candidates = items.filter { $0.matches(kind: kind, fileExtension: fileExtension) }
        guard !query.isEmpty else { return candidates }
        let scored: [(item: ClipboardItem, score: Int)] = candidates.compactMap { item in
            guard let s = fuzzyScore(query: query, candidate: item.preview) else { return nil }
            return (item, s)
        }
        return scored.sorted { a, b in
            if a.item.pinned != b.item.pinned { return a.item.pinned }
            if a.score != b.score { return a.score > b.score }
            return a.item.createdAt > b.item.createdAt
        }.map(\.item)
    }

    public func distinctFileExtensions() -> [String] {
        let extensions = items
            .filter { $0.kind == .file }
            .flatMap { $0.filePaths }
            .map { ($0 as NSString).pathExtension.lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(extensions)).sorted()
    }
}
