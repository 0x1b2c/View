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

    func testBeginNewSessionInserts() throws {
        let store = try SessionStore(dbQueue: try DatabaseQueue())
        let id = try store.beginNewSession()
        XCTAssertGreaterThan(id, 0)

        try store.reader.read { db in
            let count =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NULL")
                ?? -1
            XCTAssertEqual(count, 1)
        }
    }

    func testArchiveActiveSession() throws {
        let store = try SessionStore(dbQueue: try DatabaseQueue())
        _ = try store.beginNewSession()
        try store.archiveActiveSession()

        try store.reader.read { db in
            let active =
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NULL")
                ?? -1
            XCTAssertEqual(active, 0)
            let archived =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NOT NULL") ?? -1
            XCTAssertEqual(archived, 1)
        }
    }

    func testRoundTripSnapshot() throws {
        let store = try SessionStore(dbQueue: try DatabaseQueue())
        let sessionId = try store.beginNewSession()

        let windowId = try store.insertWindow(
            WindowRow(
                sessionId: sessionId, frameX: 100, frameY: 200, frameW: 1280, frameH: 800, zOrder: 0
            )
        )

        _ = try store.insertTab(
            TabRow(
                windowId: windowId, url: "https://example.com", title: "Example", position: 0,
                isActive: true)
        )
        _ = try store.insertTab(
            TabRow(
                windowId: windowId, url: "https://news.ycombinator.com", title: "HN", position: 1,
                isActive: false)
        )

        let snapshot = try store.loadLatestSnapshot()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.session.id, sessionId)
        XCTAssertEqual(snapshot?.windowsWithTabs.count, 1)
        XCTAssertEqual(snapshot?.windowsWithTabs[0].tabs.count, 2)
        XCTAssertEqual(snapshot?.windowsWithTabs[0].tabs[0].url, "https://example.com")
        XCTAssertTrue(snapshot?.windowsWithTabs[0].tabs[0].isActive ?? false)
    }

    func testDeleteWindowCascadesToTabs() throws {
        let store = try SessionStore(dbQueue: try DatabaseQueue())
        let sessionId = try store.beginNewSession()
        let windowId = try store.insertWindow(
            WindowRow(
                sessionId: sessionId, frameX: 0, frameY: 0, frameW: 800, frameH: 600, zOrder: 0)
        )
        _ = try store.insertTab(
            TabRow(
                windowId: windowId, url: "https://a.com", title: nil, position: 0, isActive: true)
        )
        _ = try store.insertTab(
            TabRow(
                windowId: windowId, url: "https://b.com", title: nil, position: 1, isActive: false)
        )

        try store.deleteWindow(id: windowId)

        try store.reader.read { db in
            let tabCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tabs") ?? -1
            XCTAssertEqual(tabCount, 0)
        }
    }
}
