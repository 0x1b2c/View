import XCTest

@testable import ViewCore

final class SettingsTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testDefaultsRoundtrip() throws {
        let file = tempRoot.appendingPathComponent("settings.toml")
        let defaults = Settings.defaults
        try defaults.write(to: file)
        let loaded = try Settings.read(from: file)
        XCTAssertEqual(loaded, defaults)
    }

    func testDefaultValues() {
        let defaults = Settings.defaults
        XCTAssertEqual(defaults.view.zoom, 1.0)
        XCTAssertEqual(defaults.startup.mode, .resume)
        XCTAssertTrue(defaults.vim.enabled)
        XCTAssertTrue(defaults.vim.whitelist.contains("mail.google.com"))
        XCTAssertTrue(defaults.vim.whitelist.contains("twitter.com"))
    }

    func testLoadOrCreateCreatesDefaults() throws {
        let file = tempRoot.appendingPathComponent("settings.toml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let settings = try Settings.loadOrCreate(at: file)
        XCTAssertEqual(settings, Settings.defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testLoadOrCreateReadsExisting() throws {
        let file = tempRoot.appendingPathComponent("settings.toml")
        var custom = Settings.defaults
        custom.view.zoom = 1.5
        try custom.write(to: file)
        let loaded = try Settings.loadOrCreate(at: file)
        XCTAssertEqual(loaded.view.zoom, 1.5)
    }
}
