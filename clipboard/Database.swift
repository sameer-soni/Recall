//
//  Database.swift
//  Recall
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    private var db: OpaquePointer?
    let baseDir: URL
    let imagesDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = support.appendingPathComponent("Recall", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let path = baseDir.appendingPathComponent("clipboard.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("Recall: failed to open database at \(path)")
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
            CREATE TABLE IF NOT EXISTS items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind INTEGER NOT NULL,
                content TEXT NOT NULL,
                hash TEXT UNIQUE NOT NULL,
                copy_count INTEGER NOT NULL DEFAULT 1,
                pinned INTEGER NOT NULL DEFAULT 0,
                first_copied REAL NOT NULL,
                last_copied REAL NOT NULL,
                app_name TEXT,
                app_bundle TEXT,
                byte_size INTEGER NOT NULL DEFAULT 0,
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0
            )
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_items_last ON items(last_copied DESC)")
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("Recall: sqlite error: \(String(cString: err))")
            sqlite3_free(err)
        }
    }

    // MARK: - CRUD

    func insert(kind: ClipKind, content: String, hash: String, date: Date,
                appName: String?, appBundleID: String?,
                byteSize: Int, width: Int, height: Int) -> Int64? {
        let sql = """
            INSERT INTO items(kind, content, hash, copy_count, pinned, first_copied,
                              last_copied, app_name, app_bundle, byte_size, width, height)
            VALUES(?,?,?,1,0,?,?,?,?,?,?,?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(kind.rawValue))
        sqlite3_bind_text(stmt, 2, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, hash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, date.timeIntervalSince1970)
        bindOptionalText(stmt, 6, appName)
        bindOptionalText(stmt, 7, appBundleID)
        sqlite3_bind_int64(stmt, 8, Int64(byteSize))
        sqlite3_bind_int(stmt, 9, Int32(width))
        sqlite3_bind_int(stmt, 10, Int32(height))
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func touch(id: Int64, date: Date, appName: String?, appBundleID: String?) {
        let sql = "UPDATE items SET copy_count = copy_count + 1, last_copied = ?, app_name = ?, app_bundle = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        bindOptionalText(stmt, 2, appName)
        bindOptionalText(stmt, 3, appBundleID)
        sqlite3_bind_int64(stmt, 4, id)
        sqlite3_step(stmt)
    }

    func setPinned(id: Int64, _ pinned: Bool) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE items SET pinned = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func delete(id: Int64) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM items WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func deleteUnpinned() {
        exec("DELETE FROM items WHERE pinned = 0")
    }

    /// Deletes unpinned rows beyond `limit`, returning image hashes to clean up.
    func prune(limit: Int) -> [String] {
        var doomed: [String] = []
        let sql = """
            SELECT hash FROM items
            WHERE pinned = 0 AND kind = \(ClipKind.image.rawValue) AND id IN (
                SELECT id FROM items WHERE pinned = 0
                ORDER BY last_copied DESC LIMIT -1 OFFSET \(limit)
            )
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { doomed.append(String(cString: c)) }
            }
            sqlite3_finalize(stmt)
        }
        exec("""
            DELETE FROM items WHERE pinned = 0 AND id IN (
                SELECT id FROM items WHERE pinned = 0
                ORDER BY last_copied DESC LIMIT -1 OFFSET \(limit)
            )
            """)
        return doomed
    }

    func loadAll() -> [ClipItem] {
        var items: [ClipItem] = []
        let sql = """
            SELECT id, kind, content, hash, copy_count, pinned, first_copied,
                   last_copied, app_name, app_bundle, byte_size, width, height
            FROM items ORDER BY last_copied DESC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return items }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let kind = ClipKind(rawValue: Int(sqlite3_column_int(stmt, 1))) ?? .text
            let item = ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: kind,
                content: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "",
                hash: sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "",
                copyCount: Int(sqlite3_column_int(stmt, 4)),
                isPinned: sqlite3_column_int(stmt, 5) == 1,
                firstCopied: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                lastCopied: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                appName: sqlite3_column_text(stmt, 8).map { String(cString: $0) },
                appBundleID: sqlite3_column_text(stmt, 9).map { String(cString: $0) },
                byteSize: Int(sqlite3_column_int64(stmt, 10)),
                pixelWidth: Int(sqlite3_column_int(stmt, 11)),
                pixelHeight: Int(sqlite3_column_int(stmt, 12))
            )
            items.append(item)
        }
        return items
    }

    // MARK: - Image files

    func imageURL(hash: String) -> URL {
        imagesDir.appendingPathComponent("\(hash).png")
    }

    func thumbnailURL(hash: String) -> URL {
        imagesDir.appendingPathComponent("\(hash)_thumb.png")
    }

    func removeImageFiles(hash: String) {
        try? FileManager.default.removeItem(at: imageURL(hash: hash))
        try? FileManager.default.removeItem(at: thumbnailURL(hash: hash))
    }
}
