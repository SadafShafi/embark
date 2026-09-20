//
//  SQLiteDatabase.swift
//  Emberdeck
//
//  A read-only wrapper over the system SQLite, used to read Anki's
//  collection.anki2 out of an .apkg. iOS ships SQLite, so there is nothing to
//  add to the project.
//

import Foundation
import SQLite3

/// SQLite hands back a pointer it will free itself, so text has to be copied.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLValue {
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null

    var intValue: Int64? {
        switch self {
        case .integer(let i): return i
        case .double(let d): return Int64(d)
        case .text(let t): return Int64(t)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .text(let t): return t
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        default: return nil
        }
    }
}

enum SQLiteError: LocalizedError {
    case cannotOpen(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let m): return "Could not open the collection: \(m)"
        case .queryFailed(let m): return "Could not read the collection: \(m)"
        }
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError.cannotOpen(message)
        }
        handle = db
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    /// Runs a query and materialises the rows. Anki collections are small enough
    /// that streaming would not buy anything.
    func query(_ sql: String) throws -> [[SQLValue]] {
        guard let handle else { throw SQLiteError.queryFailed("database is closed") }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_finalize(statement)
            throw SQLiteError.queryFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[SQLValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columns = sqlite3_column_count(statement)
            var row: [SQLValue] = []
            row.reserveCapacity(Int(columns))

            for c in 0..<columns {
                switch sqlite3_column_type(statement, c) {
                case SQLITE_INTEGER:
                    row.append(.integer(sqlite3_column_int64(statement, c)))
                case SQLITE_FLOAT:
                    row.append(.double(sqlite3_column_double(statement, c)))
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(statement, c) {
                        row.append(.text(String(cString: cString)))
                    } else {
                        row.append(.null)
                    }
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, c) {
                        let length = Int(sqlite3_column_bytes(statement, c))
                        row.append(.blob(Data(bytes: bytes, count: length)))
                    } else {
                        row.append(.null)
                    }
                default:
                    row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Queries that are expected to fail on older or newer Anki schemas.
    func optionalQuery(_ sql: String) -> [[SQLValue]] {
        (try? query(sql)) ?? []
    }
}
