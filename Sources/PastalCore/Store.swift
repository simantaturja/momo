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

    public func prune(maxItems: Int, maxImageBytes: Int64, imageMaxAge: TimeInterval, now: Date) throws {
        try dbQueue.write { db in
            // 1. Age out old images (non-pinned only).
            let cutoff = now.timeIntervalSince1970 - imageMaxAge
            let agedRows = try Row.fetchAll(db, sql: """
                SELECT id, imagePath FROM items
                WHERE kind = 'image' AND pinned = 0 AND createdAt < ?
                """, arguments: [cutoff])
            for row in agedRows { removeBlob(row["imagePath"]) }
            try db.execute(sql: "DELETE FROM items WHERE kind = 'image' AND pinned = 0 AND createdAt < ?", arguments: [cutoff])

            // 2. Enforce image byte cap (oldest non-pinned images first).
            var total = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(imageBytes),0) FROM items") ?? 0
            if total > maxImageBytes {
                let imgs = try Row.fetchAll(db, sql: """
                    SELECT id, imagePath, imageBytes FROM items
                    WHERE kind = 'image' AND pinned = 0 ORDER BY createdAt ASC
                    """)
                for row in imgs where total > maxImageBytes {
                    removeBlob(row["imagePath"])
                    try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [row["id"] as String])
                    total -= (row["imageBytes"] as Int64? ?? 0)
                }
            }

            // 3. Enforce item count cap on non-pinned rows (oldest first).
            let nonPinnedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE pinned = 0") ?? 0
            if nonPinnedCount > maxItems {
                let toDelete = nonPinnedCount - maxItems
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, imagePath FROM items WHERE pinned = 0
                    ORDER BY createdAt ASC LIMIT ?
                    """, arguments: [toDelete])
                for row in rows { removeBlob(row["imagePath"]) }
                try db.execute(sql: """
                    DELETE FROM items WHERE id IN (
                        SELECT id FROM items WHERE pinned = 0 ORDER BY createdAt ASC LIMIT ?
                    )
                    """, arguments: [toDelete])
            }
        }
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
