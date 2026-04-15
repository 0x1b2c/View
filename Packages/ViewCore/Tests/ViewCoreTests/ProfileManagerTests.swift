import XCTest

@testable import ViewCore

final class ProfileManagerTests: XCTestCase {
    var tempRoot: URL!
    var paths: AppPaths!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileManagerTests-\(UUID().uuidString)", isDirectory: true)
        paths = AppPaths(root: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testFirstLaunchBootstrapsDefaultProfile() throws {
        let manager = ProfileManager(paths: paths)
        let active = try manager.bootstrap()

        XCTAssertEqual(active.id, "Default")
        XCTAssertEqual(active.name, "Default")
        XCTAssertFalse(active.dataStoreUUID.isEmpty)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: paths.localStateFile.path))
        XCTAssertTrue(fm.fileExists(atPath: paths.profileDirectory(id: "Default").path))
        XCTAssertTrue(fm.fileExists(atPath: paths.webDataDirectory(profileId: "Default").path))
    }

    func testSecondLaunchReusesExistingProfile() throws {
        let firstManager = ProfileManager(paths: paths)
        let firstActive = try firstManager.bootstrap()

        let secondManager = ProfileManager(paths: paths)
        let secondActive = try secondManager.bootstrap()

        XCTAssertEqual(firstActive.dataStoreUUID, secondActive.dataStoreUUID)
    }

    func testDataStoreUUIDIsValid() throws {
        let manager = ProfileManager(paths: paths)
        let active = try manager.bootstrap()
        XCTAssertNotNil(UUID(uuidString: active.dataStoreUUID))
    }
}
