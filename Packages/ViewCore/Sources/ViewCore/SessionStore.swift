import Foundation
import GRDB

public final class SessionStore {
    public let writer: DatabaseWriter
    public var reader: DatabaseReader { writer }

    public init(dbQueue: DatabaseQueue) throws {
        self.writer = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public convenience init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbPool = try DatabasePool(path: fileURL.path, configuration: config)
        try Self.migrator.migrate(dbPool)
        self.init(writer: dbPool)
    }

    private init(writer: DatabaseWriter) {
        self.writer = writer
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1: sessions/windows/tabs") { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .text).notNull()
                t.column("closed_at", .text)
                t.column("label", .text)
            }

            try db.create(table: "windows") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer)
                    .notNull()
                    .indexed()
                    .references("sessions", onDelete: .cascade)
                t.column("frame_x", .double).notNull()
                t.column("frame_y", .double).notNull()
                t.column("frame_w", .double).notNull()
                t.column("frame_h", .double).notNull()
                t.column("z_order", .integer).notNull()
            }

            try db.create(table: "tabs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("window_id", .integer)
                    .notNull()
                    .indexed()
                    .references("windows", onDelete: .cascade)
                t.column("url", .text).notNull()
                t.column("title", .text)
                t.column("position", .integer).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2: preferences") { db in
            try db.create(table: "preferences") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        return migrator
    }

    // MARK: - Preferences

    public func getPreference(_ key: String) throws -> String? {
        try reader.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public func setPreference(_ key: String, value: String) throws {
        try writer.write { db in
            try db.execute(
                sql:
                    "INSERT INTO preferences(key, value) VALUES(?, ?) "
                    + "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value]
            )
        }
    }

    // MARK: - Session lifecycle

    public func beginNewSession() throws -> Int64 {
        try writer.write { db in
            let row = SessionRow(createdAt: ISO8601DateFormatter().string(from: Date()))
            try row.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func archiveActiveSession() throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE sessions SET closed_at = ? WHERE closed_at IS NULL",
                arguments: [ISO8601DateFormatter().string(from: Date())]
            )
        }
    }

    public func reopenSession(id: Int64) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE sessions SET closed_at = NULL WHERE id = ?",
                arguments: [id]
            )
        }
    }

    public func loadLatestSnapshot() throws -> SessionSnapshot? {
        try reader.read { db in
            guard
                let session =
                    try SessionRow
                    .order(Column("created_at").desc)
                    .fetchOne(db)
            else { return nil }

            let windows =
                try WindowRow
                .filter(Column("session_id") == session.id!)
                .order(Column("z_order"))
                .fetchAll(db)

            var combined: [(window: WindowRow, tabs: [TabRow])] = []
            for window in windows {
                let tabs =
                    try TabRow
                    .filter(Column("window_id") == window.id!)
                    .order(Column("position"))
                    .fetchAll(db)
                combined.append((window, tabs))
            }

            return SessionSnapshot(session: session, windowsWithTabs: combined)
        }
    }

    // MARK: - Window CRUD

    @discardableResult
    public func insertWindow(_ row: WindowRow) throws -> Int64 {
        try writer.write { db in
            try row.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func updateWindow(_ row: WindowRow) throws {
        try writer.write { db in
            try row.update(db)
        }
    }

    public func deleteWindow(id: Int64) throws {
        try writer.write { db in
            _ = try WindowRow.deleteOne(db, key: id)
        }
    }

    // MARK: - Tab CRUD

    @discardableResult
    public func insertTab(_ row: TabRow) throws -> Int64 {
        try writer.write { db in
            try row.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func updateTab(_ row: TabRow) throws {
        try writer.write { db in
            try row.update(db)
        }
    }

    public func deleteTab(id: Int64) throws {
        try writer.write { db in
            _ = try TabRow.deleteOne(db, key: id)
        }
    }
}
