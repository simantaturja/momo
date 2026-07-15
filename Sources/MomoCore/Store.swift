import Foundation
import GRDB

public final class Store {
    private let dbQueue: DatabaseQueue
    private let imagesDirectory: String

    public init(path: String, imagesDirectory: String) throws {
        self.imagesDirectory = imagesDirectory
        try FileManager.default.createDirectory(atPath: imagesDirectory, withIntermediateDirectories: true)
        dbQueue = path == ":memory:" ? try DatabaseQueue() : try DatabaseQueue(path: path)
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS items (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    preview TEXT NOT NULL,
                    text TEXT,
                    imagePath TEXT,
                    filePaths TEXT NOT NULL DEFAULT '',
                    createdAt DOUBLE NOT NULL,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    contentHash TEXT NOT NULL UNIQUE,
                    imageBytes INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS idx_items_order ON items(pinned DESC, createdAt DESC);
                """)
        }
    }

    public func upsert(_ item: ClipboardItem) throws {
        try dbQueue.write { db in
            if let existingId = try String.fetchOne(db,
                sql: "SELECT id FROM items WHERE contentHash = ?", arguments: [item.contentHash]) {
                try db.execute(sql: "UPDATE items SET createdAt = ? WHERE id = ?",
                               arguments: [item.createdAt.timeIntervalSince1970, existingId])
                // Dedupe hit: the existing row keeps its own blob, so the just-written
                // incoming image blob is redundant — reclaim it instead of orphaning it.
                if item.kind == .image { removeBlob(item.imagePath) }
            } else {
                try db.execute(sql: """
                    INSERT INTO items (id, kind, preview, text, imagePath, filePaths, createdAt, pinned, contentHash, imageBytes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        item.id.uuidString, item.kind.rawValue, item.preview, item.text,
                        item.imagePath, item.filePaths.joined(separator: "\n"),
                        item.createdAt.timeIntervalSince1970, item.pinned ? 1 : 0,
                        item.contentHash, imageBytesFor(item),
                    ])
            }
        }
    }

    private func imageBytesFor(_ item: ClipboardItem) -> Int64 {
        guard item.kind == .image, let rel = item.imagePath else { return 0 }
        let full = (imagesDirectory as NSString).appendingPathComponent(rel)
        let attrs = try? FileManager.default.attributesOfItem(atPath: full)
        return (attrs?[.size] as? Int64) ?? 0
    }

    public func recent(limit: Int) throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM items ORDER BY pinned DESC, createdAt DESC LIMIT ?
                """, arguments: [limit]).map(Store.decode)
        }
    }

    public func setPinned(id: UUID, pinned: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE items SET pinned = ? WHERE id = ?",
                           arguments: [pinned ? 1 : 0, id.uuidString])
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            if let rel = try String.fetchOne(db, sql: "SELECT imagePath FROM items WHERE id = ?", arguments: [id.uuidString]) {
                removeBlob(rel)
            }
            try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func writeImageBlob(_ data: Data) throws -> String {
        let name = "\(UUID().uuidString).png"
        let full = (imagesDirectory as NSString).appendingPathComponent(name)
        try data.write(to: URL(fileURLWithPath: full))
        return name
    }

    public func imageBytesTotal() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(imageBytes), 0) FROM items") ?? 0
        }
    }

    /// Enforces retention caps. Returns the number of rows deleted so the caller
    /// can skip a UI refresh when nothing changed.
    @discardableResult
    public func prune(maxItems: Int, maxImageBytes: Int64, imageMaxAge: TimeInterval, now: Date) throws -> Int {
        try dbQueue.write { db in
            var deleted = 0

            // 1. Age out old images (non-pinned only).
            let cutoff = now.timeIntervalSince1970 - imageMaxAge
            let agedRows = try Row.fetchAll(db, sql: """
                SELECT id, imagePath FROM items
                WHERE kind = 'image' AND pinned = 0 AND createdAt < ?
                """, arguments: [cutoff])
            for row in agedRows { removeBlob(row["imagePath"]) }
            deleted += try Store.deleteRows(db, ids: agedRows.map { $0["id"] as String })

            // 2. Enforce image byte cap (oldest non-pinned images first).
            var total = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(imageBytes),0) FROM items") ?? 0
            if total > maxImageBytes {
                let imgs = try Row.fetchAll(db, sql: """
                    SELECT id, imagePath, imageBytes FROM items
                    WHERE kind = 'image' AND pinned = 0 ORDER BY createdAt ASC, id ASC
                    """)
                var overflow: [String] = []
                for row in imgs where total > maxImageBytes {
                    removeBlob(row["imagePath"])
                    overflow.append(row["id"])
                    total -= (row["imageBytes"] as Int64? ?? 0)
                }
                deleted += try Store.deleteRows(db, ids: overflow)
            }

            // 3. Enforce item count cap on non-pinned rows (oldest first).
            let nonPinnedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE pinned = 0") ?? 0
            if nonPinnedCount > maxItems {
                // Delete exactly the rows whose blobs we remove — a deterministic tiebreaker
                // keeps blob-removal and row-deletion targeting the same rows under ties.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, imagePath FROM items WHERE pinned = 0
                    ORDER BY createdAt ASC, id ASC LIMIT ?
                    """, arguments: [nonPinnedCount - maxItems])
                for row in rows { removeBlob(row["imagePath"]) }
                deleted += try Store.deleteRows(db, ids: rows.map { $0["id"] as String })
            }

            return deleted
        }
    }

    /// Deletes every row and its image blob. Includes pinned items.
    public func deleteAll() throws {
        try dbQueue.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT imagePath FROM items")
            for row in rows { removeBlob(row["imagePath"]) }
            try db.execute(sql: "DELETE FROM items")
        }
    }

    /// Deletes image blob files on disk that no row references (e.g. left behind
    /// by a crash between writing a blob and committing its row). Returns the count removed.
    @discardableResult
    public func reapOrphanBlobs() throws -> Int {
        let referenced: Set<String> = try dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT imagePath FROM items WHERE imagePath IS NOT NULL"))
        }
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: imagesDirectory)) ?? []
        var removed = 0
        for name in files where !referenced.contains(name) {
            try? fm.removeItem(atPath: (imagesDirectory as NSString).appendingPathComponent(name))
            removed += 1
        }
        return removed
    }

    private static func deleteRows(_ db: Database, ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try db.execute(sql: "DELETE FROM items WHERE id IN (\(placeholders))",
                       arguments: StatementArguments(ids))
        return ids.count
    }

    private func removeBlob(_ rel: String?) {
        guard let rel, !rel.isEmpty else { return }
        let full = (imagesDirectory as NSString).appendingPathComponent(rel)
        try? FileManager.default.removeItem(atPath: full)
    }

    private static func decode(_ row: Row) -> ClipboardItem {
        let files = (row["filePaths"] as String? ?? "")
        return ClipboardItem(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            kind: ItemKind(rawValue: row["kind"]) ?? .text,
            preview: row["preview"],
            text: row["text"],
            imagePath: row["imagePath"],
            filePaths: files.isEmpty ? [] : files.components(separatedBy: "\n"),
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            pinned: (row["pinned"] as Int) == 1,
            contentHash: row["contentHash"]
        )
    }
}
