import Foundation
import TOMLKit

public struct LocalState: Codable, Equatable, Sendable {
    public var activeProfile: String
    public var profiles: [ProfileEntry]

    public init(activeProfile: String, profiles: [ProfileEntry]) {
        self.activeProfile = activeProfile
        self.profiles = profiles
    }

    public struct ProfileEntry: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var dataStoreUUID: String

        public init(id: String, name: String, dataStoreUUID: String) {
            self.id = id
            self.name = name
            self.dataStoreUUID = dataStoreUUID
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case dataStoreUUID = "data_store_uuid"
        }
    }

    enum CodingKeys: String, CodingKey {
        case activeProfile = "active_profile"
        case profiles
    }

    public static func read(from url: URL) throws -> LocalState {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LocalStateError.invalidEncoding
        }
        let decoder = TOMLDecoder()
        return try decoder.decode(LocalState.self, from: text)
    }

    public func write(to url: URL) throws {
        let encoder = TOMLEncoder()
        let text = try encoder.encode(self)
        let data = Data(text.utf8)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }
}

public enum LocalStateError: Error {
    case invalidEncoding
}
