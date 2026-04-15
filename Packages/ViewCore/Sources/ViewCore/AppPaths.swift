import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: AppPaths {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return AppPaths(root: appSupport.appendingPathComponent("View", isDirectory: true))
    }

    public var localStateFile: URL {
        root.appendingPathComponent("Local State.toml", isDirectory: false)
    }

    public var profilesRoot: URL {
        root.appendingPathComponent("Profiles", isDirectory: true)
    }

    public func profileDirectory(id: String) -> URL {
        profilesRoot.appendingPathComponent(id, isDirectory: true)
    }

    public func settingsFile(profileId: String) -> URL {
        profileDirectory(id: profileId)
            .appendingPathComponent("settings.toml", isDirectory: false)
    }

    public func sessionDatabase(profileId: String) -> URL {
        profileDirectory(id: profileId)
            .appendingPathComponent("view.sqlite", isDirectory: false)
    }

    public func webDataDirectory(profileId: String) -> URL {
        profileDirectory(id: profileId)
            .appendingPathComponent("WebData", isDirectory: true)
    }
}
