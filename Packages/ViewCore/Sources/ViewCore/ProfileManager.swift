import Foundation

public struct Profile: Equatable, Sendable {
    public let id: String
    public let name: String
    public let dataStoreUUID: String
}

public final class ProfileManager {
    private let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func bootstrap() throws -> Profile {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)

        let localState: LocalState
        if fm.fileExists(atPath: paths.localStateFile.path) {
            localState = try LocalState.read(from: paths.localStateFile)
        } else {
            let defaultEntry = LocalState.ProfileEntry(
                id: "Default",
                name: "Default",
                dataStoreUUID: UUID().uuidString
            )
            let state = LocalState(activeProfile: "Default", profiles: [defaultEntry])
            try state.write(to: paths.localStateFile)
            localState = state
        }

        guard
            let activeEntry = localState.profiles.first(where: { $0.id == localState.activeProfile }
            )
        else {
            throw ProfileManagerError.activeProfileMissing(id: localState.activeProfile)
        }

        let profileDir = paths.profileDirectory(id: activeEntry.id)
        try fm.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: paths.webDataDirectory(profileId: activeEntry.id), withIntermediateDirectories: true
        )

        return Profile(
            id: activeEntry.id,
            name: activeEntry.name,
            dataStoreUUID: activeEntry.dataStoreUUID
        )
    }
}

public enum ProfileManagerError: Error {
    case activeProfileMissing(id: String)
}
