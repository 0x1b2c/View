import XCTest
@testable import ViewCore

final class AppPathsTests: XCTestCase {
    func testDefaultRootIsApplicationSupport() {
        let paths = AppPaths.default
        let expected = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("View", isDirectory: true)
        XCTAssertEqual(paths.root.standardizedFileURL, expected.standardizedFileURL)
    }

    func testRootOverride() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPathsTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        XCTAssertEqual(paths.root, tempRoot)
    }

    func testLocalStateFilePath() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        XCTAssertEqual(
            paths.localStateFile,
            tempRoot.appendingPathComponent("Local State.toml", isDirectory: false)
        )
    }

    func testProfileDirectory() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        let profileDir = paths.profileDirectory(id: "Default")
        XCTAssertEqual(
            profileDir,
            tempRoot
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent("Default", isDirectory: true)
        )
    }

    func testProfileSubpaths() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(root: tempRoot)
        let profileDir = paths.profileDirectory(id: "Default")
        XCTAssertEqual(
            paths.settingsFile(profileId: "Default"),
            profileDir.appendingPathComponent("settings.toml", isDirectory: false)
        )
        XCTAssertEqual(
            paths.sessionDatabase(profileId: "Default"),
            profileDir.appendingPathComponent("view.sqlite", isDirectory: false)
        )
        XCTAssertEqual(
            paths.webDataDirectory(profileId: "Default"),
            profileDir.appendingPathComponent("WebData", isDirectory: true)
        )
    }
}
