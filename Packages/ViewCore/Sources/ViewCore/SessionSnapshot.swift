import Foundation
import GRDB

public struct SessionRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    public var id: Int64?
    public var createdAt: String
    public var closedAt: String?
    public var label: String?

    public static let databaseTableName = "sessions"

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case closedAt = "closed_at"
        case label
    }

    public init(id: Int64? = nil, createdAt: String, closedAt: String? = nil, label: String? = nil)
    {
        self.id = id
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.label = label
    }
}

public struct WindowRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    public var id: Int64?
    public var sessionId: Int64
    public var frameX: Double
    public var frameY: Double
    public var frameW: Double
    public var frameH: Double
    public var zOrder: Int

    public static let databaseTableName = "windows"

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case frameX = "frame_x"
        case frameY = "frame_y"
        case frameW = "frame_w"
        case frameH = "frame_h"
        case zOrder = "z_order"
    }

    public init(
        id: Int64? = nil,
        sessionId: Int64,
        frameX: Double,
        frameY: Double,
        frameW: Double,
        frameH: Double,
        zOrder: Int
    ) {
        self.id = id
        self.sessionId = sessionId
        self.frameX = frameX
        self.frameY = frameY
        self.frameW = frameW
        self.frameH = frameH
        self.zOrder = zOrder
    }
}

public struct TabRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    public var id: Int64?
    public var windowId: Int64
    public var url: String
    public var title: String?
    public var position: Int
    public var isActive: Bool

    public static let databaseTableName = "tabs"

    enum CodingKeys: String, CodingKey {
        case id
        case windowId = "window_id"
        case url
        case title
        case position
        case isActive = "is_active"
    }

    public init(
        id: Int64? = nil,
        windowId: Int64,
        url: String,
        title: String? = nil,
        position: Int,
        isActive: Bool
    ) {
        self.id = id
        self.windowId = windowId
        self.url = url
        self.title = title
        self.position = position
        self.isActive = isActive
    }
}

public struct SessionSnapshot: Equatable {
    public var session: SessionRow
    public var windowsWithTabs: [(window: WindowRow, tabs: [TabRow])]

    public static func == (lhs: SessionSnapshot, rhs: SessionSnapshot) -> Bool {
        guard lhs.session == rhs.session else { return false }
        guard lhs.windowsWithTabs.count == rhs.windowsWithTabs.count else { return false }
        for (left, right) in zip(lhs.windowsWithTabs, rhs.windowsWithTabs) {
            if left.window != right.window || left.tabs != right.tabs { return false }
        }
        return true
    }

    public init(session: SessionRow, windowsWithTabs: [(window: WindowRow, tabs: [TabRow])]) {
        self.session = session
        self.windowsWithTabs = windowsWithTabs
    }
}
