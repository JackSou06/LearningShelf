import Foundation
import SQLite3

final class RecordStore {
    private var db: OpaquePointer?
    let folder: URL
    init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard sqlite3_open(folder.appendingPathComponent("learning.sqlite").path, &db) == SQLITE_OK else { throw CourseFailure(message: "無法開啟學習紀錄資料庫") }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, payload BLOB NOT NULL, previous BLOB, updated REAL);")
    }
    deinit { sqlite3_close(db) }
    func checkpoint() throws { try execute("PRAGMA wal_checkpoint(FULL);") }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CourseFailure(message: "資料庫寫入失敗") } }
    func load(_ id: String) throws -> [String: Any]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM records WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { throw CourseFailure(message: "讀取紀錄失敗") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(stmt) == SQLITE_ROW {
            let size = Int(sqlite3_column_bytes(stmt, 0))
            guard let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
            return try JSONSerialization.jsonObject(with: Data(bytes: bytes, count: size)) as? [String: Any]
        }
        return nil
    }
    func save(_ record: [String: Any]) throws {
        guard let id = record["courseId"] as? String, record["format"] as? String == "learning-records", let version = record["version"] as? Int, version == 1 else { throw CourseFailure(message: "學習紀錄格式錯誤") }
        let data = try JSONSerialization.data(withJSONObject: record)
        guard data.count <= 10_000_000 else { throw CourseFailure(message: "紀錄超過 10 MB，請先匯出備份") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO records(id,payload,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET previous=records.payload,payload=excluded.payload,updated=excluded.updated", -1, &stmt, nil) == SQLITE_OK else { throw CourseFailure(message: "保存紀錄失敗") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CourseFailure(message: "保存紀錄失敗，請匯出備份") }
    }
}
