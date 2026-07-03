import Foundation
import GRDB

// MARK: – Value type stored in the database

struct IndexedFile: Sendable {
    let path: String
    let name: String          // display name (without extension)
    let ext: String           // lowercased file extension
    let size: Int64
    let modifiedAt: Double    // Unix timestamp
    let ruleId: String
    let acronym: String       // first letter of each word, lowercased ("Visual Studio Code" → "vsc")
}

// MARK: – Search index

/// Wraps a GRDB `DatabaseQueue` providing FTS5-backed file search.
/// All public methods are safe to call from any thread / Task.
final class SearchIndex: Sendable {

    private let dbQueue: DatabaseQueue

    // MARK: – Init

    init() throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Sift", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent("index.db").path
        var config = Configuration()
        config.busyMode = .timeout(10)

        dbQueue = try Self.openQueue(at: dbPath, configuration: config)
        try Self.setupSchema(dbQueue)
    }

    // MARK: – Schema

    /// Opens the database at `path`, validating that the schema is current.
    /// If the file is missing, malformed, or has a stale schema it is deleted
    /// and a fresh empty database is returned. No migration logic needed — the
    /// index is always rebuilt from scratch by IndexManager on launch.
    private static func openQueue(at path: String, configuration: Configuration) throws -> DatabaseQueue {
        if FileManager.default.fileExists(atPath: path) {
            if let queue = try? DatabaseQueue(path: path, configuration: configuration) {
                // Probe for the acronym column; its absence means this is an old schema.
                let schemaOK = (try? queue.read { db in
                    _ = try Row.fetchOne(db, sql: "SELECT acronym FROM files LIMIT 0")
                    return true
                }) == true
                if schemaOK { return queue }
            }
            // Malformed or outdated — remove and fall through to a fresh file.
            try? FileManager.default.removeItem(atPath: path)
        }
        return try DatabaseQueue(path: path, configuration: configuration)
    }

    private static func setupSchema(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS files (
                    path       TEXT PRIMARY KEY,
                    name       TEXT NOT NULL,
                    ext        TEXT NOT NULL DEFAULT '',
                    size       INTEGER NOT NULL DEFAULT 0,
                    modifiedAt REAL NOT NULL DEFAULT 0,
                    ruleId     TEXT NOT NULL,
                    acronym    TEXT NOT NULL DEFAULT ''
                )
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                    name,
                    acronym,
                    content=files,
                    content_rowid=rowid,
                    tokenize='unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
                    INSERT INTO files_fts(rowid, name, acronym)
                    VALUES (new.rowid, new.name, new.acronym);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, name, acronym)
                    VALUES('delete', old.rowid, old.name, old.acronym);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, name, acronym)
                    VALUES('delete', old.rowid, old.name, old.acronym);
                    INSERT INTO files_fts(rowid, name, acronym)
                    VALUES (new.rowid, new.name, new.acronym);
                END
                """)
        }
    }

    // MARK: – Write

    func upsert(_ file: IndexedFile) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO files (path, name, ext, size, modifiedAt, ruleId, acronym)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [file.path, file.name, file.ext, file.size, file.modifiedAt, file.ruleId, file.acronym])
        }
    }

    func bulkUpsert(_ files: [IndexedFile]) throws {
        guard !files.isEmpty else { return }
        try dbQueue.write { db in
            for file in files {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO files (path, name, ext, size, modifiedAt, ruleId, acronym)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [file.path, file.name, file.ext, file.size, file.modifiedAt, file.ruleId, file.acronym])
            }
        }
    }

    func delete(path: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM files WHERE path = ?", arguments: [path])
        }
    }

    func deleteByRule(ruleId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM files WHERE ruleId = ?", arguments: [ruleId])
        }
    }

    // MARK: – Read / Search

    func search(query: String, extensions: [String]? = nil, limit: Int = 50) throws -> [SearchResult] {
        let ftsQuery = FileTypeFilter.prepareFTSQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        // Used for the prefix-rank check: does the display name start with the
        // raw query? This lets us surface "VS Code" before "Visual Studio Code"
        // when the user types "vs code" (the latter matches via acronym column).
        let queryLower = query.trimmingCharacters(in: .whitespaces).lowercased()

        return try dbQueue.read { db in
            // FTS5 MATCH searches ALL columns (name + acronym) by default, so
            // a query like "vs* AND code*" finds:
            //   • rank 0 – files whose display name starts with the raw query
            //   • rank 1 – acronym / mid-word matches (e.g. "vsc" in "Visual Studio Code")
            // Within each rank, shorter names sort first (more specific match).
            var sql = """
                SELECT path, name, ext,
                    CASE WHEN lower(name) LIKE ? THEN 0 ELSE 1 END AS rank
                FROM files
                WHERE rowid IN (
                    SELECT rowid FROM files_fts WHERE files_fts MATCH ?
                )
                """
            var args: [DatabaseValueConvertible] = [queryLower + "%", ftsQuery]

            if let exts = extensions, !exts.isEmpty {
                let placeholders = exts.map { _ in "?" }.joined(separator: ", ")
                sql += " AND ext IN (\(placeholders))"
                args.append(contentsOf: exts.map { $0 as DatabaseValueConvertible })
            }

            sql += " ORDER BY rank, length(name) LIMIT ?"
            args.append(limit)

            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                .map { row -> SearchResult in
                    let path = row["path"] as! String
                    let name = row["name"] as! String
                    let ext  = row["ext"]  as! String
                    return SearchResult(
                        id: path,
                        name: name,
                        path: path,
                        url: URL(fileURLWithPath: path),
                        fileExtension: ext
                    )
                }
        }
    }

    func count(ruleId: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM files WHERE ruleId = ?",
                             arguments: [ruleId]) ?? 0
        }
    }
}
