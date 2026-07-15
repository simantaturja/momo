import Foundation

public final class HistoryIndex {
    private var items: [ClipboardItem] = []

    public init() {}

    public func replaceAll(_ items: [ClipboardItem]) {
        self.items = items
    }

    public func prepend(_ item: ClipboardItem) {
        items.removeAll { $0.contentHash == item.contentHash }
        items.insert(item, at: 0)
    }

    public func search(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        let scored: [(item: ClipboardItem, score: Int)] = items.compactMap { item in
            guard let s = fuzzyScore(query: query, candidate: item.preview) else { return nil }
            return (item, s)
        }
        return scored.sorted { a, b in
            if a.item.pinned != b.item.pinned { return a.item.pinned }
            if a.score != b.score { return a.score > b.score }
            return a.item.createdAt > b.item.createdAt
        }.map(\.item)
    }
}
