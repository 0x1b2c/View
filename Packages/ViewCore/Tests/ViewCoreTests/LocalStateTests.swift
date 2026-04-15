import XCTest
@testable import ViewCore

final class LocalStateTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testWriteAndReadRoundtrip() throws {
        let file = tempRoot.appendingPathComponent("Local State.toml")
        let original = LocalState(
            activeProfile: "Default",
            profiles: [
                LocalState.ProfileEntry(
                    id: "Default",
                    name: "Default",
                    dataStoreUUID: "11111111-1111-1111-1111-111111111111"
                )
            ]
        )
        try original.write(to: file)
        let loaded = try LocalState.read(from: file)
        XCTAssertEqual(loaded, original)
    }

    func testReadMissingFileThrows() {
        let file = tempRoot.appendingPathComponent("Local State.toml")
        XCTAssertThrowsError(try LocalState.read(from: file))
    }

    func testWriteIsAtomic() throws {
        let file = tempRoot.appendingPathComponent("Local State.toml")
        let state = LocalState(
            activeProfile: "Default",
            profiles: [
                LocalState.ProfileEntry(id: "Default", name: "Default", dataStoreUUID: "abc")
            ]
        )
        try state.write(to: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
        XCTAssertEqual(
            contents.filter { $0.hasPrefix("Local State") }.sorted(), ["Local State.toml"])
    }
}
