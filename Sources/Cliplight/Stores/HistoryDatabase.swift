import Foundation
import SQLite3
import CryptoKit

/// Clip history in SQLite. Every row is sealed with AES-GCM, so the file is unreadable without the Keychain key.
/// Not thread-safe: the store calls it from one serial queue.
final class HistoryDatabase: @unchecked Sendable {
    private var db: OpaquePointer?
    private let key: SymmetricKey
    private(set) var unreadableRows = 0

    init(url: URL, key: SymmetricKey) throws {
        self.key = key
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw failure("open")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try exec("PRAGMA secure_delete = ON")
        try exec("CREATE TABLE IF NOT EXISTS clips (id TEXT PRIMARY KEY, sealed BLOB NOT NULL)")
    }
    deinit { sqlite3_close(db) }

    func loadAll() throws -> [Clip] {
        let statement = try prepare("SELECT sealed FROM clips")
        defer { sqlite3_finalize(statement) }
        var clips: [Clip] = []
        unreadableRows = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let sealed = Data(bytes: bytes, count: count)
            if let box = try? AES.GCM.SealedBox(combined: sealed),
               let plain = try? AES.GCM.open(box, using: key),
               let clip = try? JSONDecoder().decode(Clip.self, from: plain) {
                clips.append(clip)
            } else {
                unreadableRows += 1
            }
        }
        return clips
    }

    func upsert(_ clips: [Clip]) throws {
        guard !clips.isEmpty else { return }
        try transaction {
            let statement = try prepare("INSERT OR REPLACE INTO clips (id, sealed) VALUES (?, ?)")
            defer { sqlite3_finalize(statement) }
            for clip in clips {
                let plain = try JSONEncoder().encode(clip)
                guard let sealed = try AES.GCM.seal(plain, using: key).combined else { continue }
                sqlite3_reset(statement)
                sqlite3_bind_text(statement, 1, clip.id.uuidString, -1, Self.transient)
                _ = sealed.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(sealed.count), Self.transient) }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("write") }
            }
        }
    }

    func delete(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            let statement = try prepare("DELETE FROM clips WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            for id in ids {
                sqlite3_reset(statement)
                sqlite3_bind_text(statement, 1, id.uuidString, -1, Self.transient)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("delete") }
            }
        }
    }

    func deleteAll() throws {
        try exec("DELETE FROM clips")
        try exec("VACUUM")
    }

    // MARK: - SQLite plumbing

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure(sql) }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure(sql) }
        return statement
    }
    private func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE")
        do { try body(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }
    private func failure(_ action: String) -> Error {
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "History database \(action) failed: \(message)"])
    }
}
