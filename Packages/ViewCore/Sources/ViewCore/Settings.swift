import Foundation
import TOMLKit

public struct Settings: Codable, Equatable, Sendable {
    public var view: ViewSection
    public var startup: StartupSection
    public var vim: VimSection

    public init(view: ViewSection, startup: StartupSection, vim: VimSection) {
        self.view = view
        self.startup = startup
        self.vim = vim
    }

    public struct ViewSection: Codable, Equatable, Sendable {
        public var zoom: Double
        public init(zoom: Double) { self.zoom = zoom }
    }

    public struct StartupSection: Codable, Equatable, Sendable {
        public var mode: StartupMode
        public init(mode: StartupMode) { self.mode = mode }
    }

    public enum StartupMode: String, Codable, Sendable {
        case resume
        case blank
    }

    public struct VimSection: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var whitelist: [String]
        public init(enabled: Bool, whitelist: [String]) {
            self.enabled = enabled
            self.whitelist = whitelist
        }
    }

    public static let defaults = Settings(
        view: ViewSection(zoom: 1.0),
        startup: StartupSection(mode: .resume),
        vim: VimSection(
            enabled: true,
            whitelist: [
                "mail.google.com",
                "twitter.com",
                "x.com",
                "reddit.com",
                "youtube.com",
            ]
        )
    )

    public static func read(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SettingsError.invalidEncoding
        }
        return try TOMLDecoder().decode(Settings.self, from: text)
    }

    public func write(to url: URL) throws {
        let text = try TOMLEncoder().encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url, options: [.atomic])
    }

    public static func loadOrCreate(at url: URL) throws -> Settings {
        if FileManager.default.fileExists(atPath: url.path) {
            return try Settings.read(from: url)
        }
        try Settings.defaults.write(to: url)
        return Settings.defaults
    }
}

public enum SettingsError: Error {
    case invalidEncoding
}
