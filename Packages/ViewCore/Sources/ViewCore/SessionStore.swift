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

        return migrator
    }
}
