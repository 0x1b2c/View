import XCTest
import GRDB
@testable import ViewCore

final class SessionStoreTests: XCTestCase {
    func testMigrationOnInMemoryDatabase() throws {
        let dbQueue = try DatabaseQueue()
        let store = try SessionStore(dbQueue: dbQueue)

        try store.reader.read { db in
            let sessionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions") ?? -1
            XCTAssertEqual(sessionCount, 0)

            let windowCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM windows") ?? -1
            XCTAssertEqual(windowCount, 0)

            let tabCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tabs") ?? -1
            XCTAssertEqual(tabCount, 0)
        }
    }

    func testWALModeIsEnabledForFileDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("view.sqlite")
        let store = try SessionStore(fileURL: dbURL)

        try store.reader.read { db in
            let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
            XCTAssertEqual(mode.lowercased(), "wal")
        }
    }

    func testForeignKeysAreEnforced() throws {
        let dbQueue = try DatabaseQueue()
        let store = try SessionStore(dbQueue: dbQueue)

        try store.writer.write { db in
            try db.execute(
                sql: "INSERT INTO sessions (created_at, closed_at, label) VALUES (?, NULL, NULL)",
                arguments: ["2026-04-15T00:00:00Z"]
            )
        }

        XCTAssertThrowsError(
            try store.writer.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO windows (session_id, frame_x, frame_y, frame_w, frame_h, z_order) VALUES (999, 0, 0, 100, 100, 0)"
                )
            }
        )
    }
}
