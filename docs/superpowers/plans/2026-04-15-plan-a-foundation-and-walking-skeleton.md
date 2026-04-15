# Plan A: Foundation and Walking Skeleton

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap the View browser project into a working single-window, single-tab state with the profile directory layout, TOML settings, SQLite session store, and WKWebView data store isolation all wired up and tested. No multi-tab, no session restore, no Vim, no error UI — those come in later plans.

**Architecture:** A local Swift Package `Packages/ViewCore` contains all pure logic (paths, profile, settings, sessions) and is added to the Xcode app as a local SPM dependency. The app target contains only AppKit/WKWebView code and calls into `ViewCore`. All tests for `ViewCore` run via `swift test --package-path Packages/ViewCore` without launching Xcode.

**Tech Stack:** Swift 5.9+, AppKit, WKWebView, Swift Package Manager, GRDB.swift (SQLite), TOMLKit (TOML), XCTest.

**Spec reference:** `docs/superpowers/specs/2026-04-15-view-browser-design.md`

---

## File Structure

```
View/                                                (git root)
├── View.xcodeproj                                   (existing, modified)
├── View/                                            (app target, existing)
│   ├── AppDelegate.swift                            (rewritten)
│   ├── BrowserWindowController.swift                (new)
│   ├── ViewController.swift                         (deleted)
│   └── Base.lproj/Main.storyboard                   (simplified: just MainMenu)
├── Packages/
│   └── ViewCore/                                    (new local Swift package)
│       ├── Package.swift
│       ├── Sources/
│       │   └── ViewCore/
│       │       ├── AppPaths.swift                   (data directory resolution)
│       │       ├── LocalState.swift                 (Local State.toml model + I/O)
│       │       ├── ProfileManager.swift             (profile bootstrap + active profile)
│       │       ├── Settings.swift                   (settings.toml model + I/O)
│       │       ├── SessionStore.swift               (GRDB + schema migrations)
│       │       └── Models.swift                     (SessionRecord, WindowRecord, TabRecord)
│       └── Tests/
│           └── ViewCoreTests/
│               ├── AppPathsTests.swift
│               ├── LocalStateTests.swift
│               ├── ProfileManagerTests.swift
│               ├── SettingsTests.swift
│               └── SessionStoreTests.swift
└── docs/                                            (existing)
```

**Responsibilities:**

- **AppPaths**: computes `~/Library/Application Support/View/`, `Profiles/<id>/`, the log directory, and accepts a root override for tests.
- **LocalState**: Codable TOML model for `Local State.toml`, with atomic read and write.
- **ProfileManager**: ensures the data directory exists, bootstraps a Default profile on first launch, returns the active `Profile` (including its `data_store_uuid`), creates profile subdirectories.
- **Settings**: Codable TOML model for `settings.toml`, provides defaults, atomic read and write, and an observable change-notification mechanism.
- **SessionStore**: opens `view.sqlite` via GRDB, runs migrations, exposes typed methods. Plan A creates the schema but does not yet use it for restore — Plan B consumes it.
- **BrowserWindowController** (app target): programmatic NSWindow hosting a single WKWebView, accepts a `WKWebViewConfiguration` from the caller.
- **AppDelegate** (app target): on launch, bootstraps `ProfileManager`, reads `Settings`, constructs a `WKWebViewConfiguration` with `WKWebsiteDataStore(forIdentifier:)`, opens one `BrowserWindowController` with one WKWebView loading a hardcoded URL.

---

## Task 1: Create the Local Swift Package `ViewCore`

**Files:**
- Create: `Packages/ViewCore/Package.swift`
- Create: `Packages/ViewCore/Sources/ViewCore/ViewCore.swift` (placeholder)
- Create: `Packages/ViewCore/Tests/ViewCoreTests/SmokeTest.swift`

- [ ] **Step 1.1: Create the package directory structure**

```bash
mkdir -p Packages/ViewCore/Sources/ViewCore
mkdir -p Packages/ViewCore/Tests/ViewCoreTests
```

- [ ] **Step 1.2: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ViewCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ViewCore",
            targets: ["ViewCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "ViewCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "TOMLKit", package: "TOMLKit")
            ]
        ),
        .testTarget(
            name: "ViewCoreTests",
            dependencies: ["ViewCore"]
        )
    ]
)
```

- [ ] **Step 1.3: Create placeholder source file**

`Packages/ViewCore/Sources/ViewCore/ViewCore.swift`:

```swift
public enum ViewCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 1.4: Create smoke test**

`Packages/ViewCore/Tests/ViewCoreTests/SmokeTest.swift`:

```swift
import XCTest
@testable import ViewCore

final class SmokeTest: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(ViewCore.version, "0.1.0")
    }
}
```

- [ ] **Step 1.5: Resolve dependencies and run tests**

Run: `swift test --package-path Packages/ViewCore`
Expected: dependencies resolve, `testVersionIsSet` passes.

- [ ] **Step 1.6: Commit**

```bash
git add Packages/ViewCore
git commit -m "Bootstrap ViewCore local package with GRDB and TOMLKit"
```

---

## Task 2: Add `ViewCore` as a Local Package Dependency to the Xcode App

This task is performed in the Xcode GUI because editing `project.pbxproj` by hand is fragile. The steps below describe the GUI actions precisely.

**Files:**
- Modify: `View.xcodeproj/project.pbxproj` (via Xcode)

- [ ] **Step 2.1: Open the project in Xcode**

Run: `open View.xcodeproj`

- [ ] **Step 2.2: Add the local package**

In Xcode:
1. Select the `View` project in the Project Navigator.
2. Select the `View` project (not the target) in the editor.
3. Go to the `Package Dependencies` tab.
4. Click the `+` button.
5. Click `Add Local...` at the bottom left.
6. Navigate to and select `Packages/ViewCore`.
7. Click `Add Package`.
8. In the `Choose Package Products` dialog, confirm `ViewCore` is added to the `View` app target.

- [ ] **Step 2.3: Verify the app builds with the dependency**

In Xcode, press Cmd-B.
Expected: Build succeeds.

- [ ] **Step 2.4: Verify `import ViewCore` works**

Modify `View/AppDelegate.swift` to add `import ViewCore` at the top and log the version in `applicationDidFinishLaunching`:

```swift
import Cocoa
import ViewCore

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSLog("ViewCore version: %@", ViewCore.version)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
```

- [ ] **Step 2.5: Build and run**

In Xcode, press Cmd-R.
Expected: App launches, empty window appears, console shows `ViewCore version: 0.1.0`.
Then quit the app.

- [ ] **Step 2.6: Commit**

```bash
git add View.xcodeproj View/AppDelegate.swift
git commit -m "Link ViewCore local package to app target"
```

---

## Task 3: Implement `AppPaths`

`AppPaths` resolves all filesystem paths used by the app. It must accept a root override so tests can point it at a temporary directory.

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/AppPaths.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/AppPathsTests.swift`

- [ ] **Step 3.1: Write failing tests**

`Packages/ViewCore/Tests/ViewCoreTests/AppPathsTests.swift`:

```swift
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
```

- [ ] **Step 3.2: Run tests to verify they fail**

Run: `swift test --package-path Packages/ViewCore --filter AppPathsTests`
Expected: FAIL with "cannot find 'AppPaths' in scope".

- [ ] **Step 3.3: Write implementation**

`Packages/ViewCore/Sources/ViewCore/AppPaths.swift`:

```swift
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
```

- [ ] **Step 3.4: Run tests to verify they pass**

Run: `swift test --package-path Packages/ViewCore --filter AppPathsTests`
Expected: All `AppPathsTests` pass.

- [ ] **Step 3.5: Commit**

```bash
git add Packages/ViewCore/Sources/ViewCore/AppPaths.swift Packages/ViewCore/Tests/ViewCoreTests/AppPathsTests.swift
git commit -m "Add AppPaths for data directory resolution"
```

---

## Task 4: Implement `LocalState` TOML Read and Write

`LocalState` is the Codable model for `Local State.toml`. It tracks known profiles and the active one.

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/LocalState.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/LocalStateTests.swift`

- [ ] **Step 4.1: Write failing tests**

`Packages/ViewCore/Tests/ViewCoreTests/LocalStateTests.swift`:

```swift
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
        // Confirm no leftover temp file is present next to it.
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
        XCTAssertEqual(contents.filter { $0.hasPrefix("Local State") }.sorted(), ["Local State.toml"])
    }
}
```

- [ ] **Step 4.2: Run tests to verify they fail**

Run: `swift test --package-path Packages/ViewCore --filter LocalStateTests`
Expected: FAIL with "cannot find 'LocalState' in scope".

- [ ] **Step 4.3: Write implementation**

`Packages/ViewCore/Sources/ViewCore/LocalState.swift`:

```swift
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
```

- [ ] **Step 4.4: Run tests to verify they pass**

Run: `swift test --package-path Packages/ViewCore --filter LocalStateTests`
Expected: All `LocalStateTests` pass.

- [ ] **Step 4.5: Commit**

```bash
git add Packages/ViewCore/Sources/ViewCore/LocalState.swift Packages/ViewCore/Tests/ViewCoreTests/LocalStateTests.swift
git commit -m "Add LocalState TOML model with atomic read/write"
```

---

## Task 5: Implement `ProfileManager`

`ProfileManager` is the bootstrap. On first launch it creates `Local State.toml`, a Default profile, and the profile's subdirectories.

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/ProfileManager.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/ProfileManagerTests.swift`

- [ ] **Step 5.1: Write failing tests**

`Packages/ViewCore/Tests/ViewCoreTests/ProfileManagerTests.swift`:

```swift
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
```

- [ ] **Step 5.2: Run tests to verify they fail**

Run: `swift test --package-path Packages/ViewCore --filter ProfileManagerTests`
Expected: FAIL with "cannot find 'ProfileManager' in scope".

- [ ] **Step 5.3: Write implementation**

`Packages/ViewCore/Sources/ViewCore/ProfileManager.swift`:

```swift
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

        guard let activeEntry = localState.profiles.first(where: { $0.id == localState.activeProfile }) else {
            throw ProfileManagerError.activeProfileMissing(id: localState.activeProfile)
        }

        let profileDir = paths.profileDirectory(id: activeEntry.id)
        try fm.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.webDataDirectory(profileId: activeEntry.id), withIntermediateDirectories: true)

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
```

- [ ] **Step 5.4: Run tests to verify they pass**

Run: `swift test --package-path Packages/ViewCore --filter ProfileManagerTests`
Expected: All `ProfileManagerTests` pass.

- [ ] **Step 5.5: Commit**

```bash
git add Packages/ViewCore/Sources/ViewCore/ProfileManager.swift Packages/ViewCore/Tests/ViewCoreTests/ProfileManagerTests.swift
git commit -m "Add ProfileManager bootstrap for default profile"
```

---

## Task 6: Implement `Settings` TOML Read and Write

`Settings` is the Codable model for `settings.toml`. It has defaults for first launch and atomic write.

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/Settings.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/SettingsTests.swift`

- [ ] **Step 6.1: Write failing tests**

`Packages/ViewCore/Tests/ViewCoreTests/SettingsTests.swift`:

```swift
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
```

- [ ] **Step 6.2: Run tests to verify they fail**

Run: `swift test --package-path Packages/ViewCore --filter SettingsTests`
Expected: FAIL with "cannot find 'Settings' in scope".

- [ ] **Step 6.3: Write implementation**

`Packages/ViewCore/Sources/ViewCore/Settings.swift`:

```swift
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
                "youtube.com"
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
```

- [ ] **Step 6.4: Run tests to verify they pass**

Run: `swift test --package-path Packages/ViewCore --filter SettingsTests`
Expected: All `SettingsTests` pass.

- [ ] **Step 6.5: Commit**

```bash
git add Packages/ViewCore/Sources/ViewCore/Settings.swift Packages/ViewCore/Tests/ViewCoreTests/SettingsTests.swift
git commit -m "Add Settings TOML model with defaults and loadOrCreate"
```

---

## Task 7: Implement `SessionStore` (GRDB Schema)

Plan A creates the database and its schema through a GRDB migration, but does not yet read or write session rows (Plan B does that). The goal of this task is to prove the schema compiles, migrates cleanly, and is testable.

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/SessionStore.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/SessionStoreTests.swift`

- [ ] **Step 7.1: Write failing tests**

`Packages/ViewCore/Tests/ViewCoreTests/SessionStoreTests.swift`:

```swift
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
                    sql: "INSERT INTO windows (session_id, frame_x, frame_y, frame_w, frame_h, z_order) VALUES (999, 0, 0, 100, 100, 0)"
                )
            }
        )
    }
}
```

- [ ] **Step 7.2: Run tests to verify they fail**

Run: `swift test --package-path Packages/ViewCore --filter SessionStoreTests`
Expected: FAIL with "cannot find 'SessionStore' in scope".

- [ ] **Step 7.3: Write implementation**

`Packages/ViewCore/Sources/ViewCore/SessionStore.swift`:

```swift
import Foundation
import GRDB

public final class SessionStore {
    public let writer: DatabaseWriter
    public var reader: DatabaseReader { writer }

    public init(dbQueue: DatabaseQueue) throws {
        self.writer = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    public convenience init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbPool = try DatabasePool(path: fileURL.path, configuration: config)
        self.writer = dbPool
        try Self.migrator.migrate(dbPool)
    }

    private init(writer: DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1: sessions/windows/tabs") { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")

            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .text).notNull()
                t.column("closed_at", .text)
                t.column("label", .text)
            }

            try db.create(table: "windows") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer)
                    .notNull()
                    .indexed()
                    .references("sessions", onDelete: .cascade)
                t.column("frame_x", .double).notNull()
                t.column("frame_y", .double).notNull()
                t.column("frame_w", .double).notNull()
                t.column("frame_h", .double).notNull()
                t.column("z_order", .integer).notNull()
            }

            try db.create(table: "tabs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("window_id", .integer)
                    .notNull()
                    .indexed()
                    .references("windows", onDelete: .cascade)
                t.column("url", .text).notNull()
                t.column("title", .text)
                t.column("position", .integer).notNull()
                t.column("is_active", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }
}
```

**Note on the `DatabaseQueue` initializer:** `DatabaseQueue()` with no arguments creates an in-memory SQLite database. PRAGMA foreign_keys for in-memory databases must be set per connection — the migration does this via `PRAGMA foreign_keys = ON`. For file-based pools, the `Configuration.foreignKeysEnabled = true` setting handles it.

- [ ] **Step 7.4: Run tests to verify they pass**

Run: `swift test --package-path Packages/ViewCore --filter SessionStoreTests`
Expected: All `SessionStoreTests` pass.

- [ ] **Step 7.5: Commit**

```bash
git add Packages/ViewCore/Sources/ViewCore/SessionStore.swift Packages/ViewCore/Tests/ViewCoreTests/SessionStoreTests.swift
git commit -m "Add SessionStore with v1 schema migration"
```

---

## Task 8: Run the Full ViewCore Test Suite

- [ ] **Step 8.1: Run all ViewCore tests**

Run: `swift test --package-path Packages/ViewCore`
Expected: All tests from all test files pass, zero failures.

- [ ] **Step 8.2: Confirm no uncommitted work**

Run: `git status`
Expected: Clean working tree.

---

## Task 9: Create `BrowserWindowController` in the App Target

This is the first AppKit code. `BrowserWindowController` owns an `NSWindow` and a single `WKWebView` filling its content view.

**Files:**
- Create: `View/BrowserWindowController.swift`
- Delete: `View/ViewController.swift`

- [ ] **Step 9.1: Delete the template view controller**

In Xcode, right-click `View/ViewController.swift` and select `Delete` > `Move to Trash`. This removes the reference from the project and deletes the file.

Also open `View/Base.lproj/Main.storyboard` and delete the `Window Controller` and `View Controller` scenes. Keep only the `Application Scene` (the one containing `MainMenu`). Save.

- [ ] **Step 9.2: Create `BrowserWindowController.swift`**

In Xcode, File > New > File > macOS > Swift File, name it `BrowserWindowController.swift`, target `View`.

Contents:

```swift
import AppKit
import WebKit

final class BrowserWindowController: NSWindowController {
    private let webView: WKWebView

    init(webViewConfiguration: WKWebViewConfiguration, initialURL: URL, zoom: Double) {
        self.webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        self.webView.pageZoom = CGFloat(zoom)
        self.webView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "View"
        window.center()

        super.init(window: window)

        guard let contentView = window.contentView else { return }
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        webView.load(URLRequest(url: initialURL))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 9.3: Build**

In Xcode, press Cmd-B.
Expected: Build succeeds with warnings only if any.

- [ ] **Step 9.4: Commit**

```bash
git add View/BrowserWindowController.swift View/Base.lproj/Main.storyboard View.xcodeproj
git rm View/ViewController.swift 2>/dev/null || true
git commit -m "Add BrowserWindowController hosting a single WKWebView"
```

---

## Task 10: Wire `AppDelegate` to Bootstrap Profile and Open a Browser Window

**Files:**
- Modify: `View/AppDelegate.swift`

- [ ] **Step 10.1: Rewrite `AppDelegate.swift`**

```swift
import Cocoa
import WebKit
import ViewCore

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var browserController: BrowserWindowController?
    private var profile: Profile?
    private var settings: Settings?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            let paths = AppPaths.default
            let profileManager = ProfileManager(paths: paths)
            let profile = try profileManager.bootstrap()
            self.profile = profile

            let settings = try Settings.loadOrCreate(at: paths.settingsFile(profileId: profile.id))
            self.settings = settings

            let sessionStore = try SessionStore(fileURL: paths.sessionDatabase(profileId: profile.id))
            _ = sessionStore  // Schema initialized; real use comes in Plan B.

            let configuration = Self.makeConfiguration(profile: profile)
            let controller = BrowserWindowController(
                webViewConfiguration: configuration,
                initialURL: URL(string: "https://example.com")!,
                zoom: settings.view.zoom
            )
            controller.showWindow(nil)
            self.browserController = controller
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "View failed to launch"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private static func makeConfiguration(profile: Profile) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        if let uuid = UUID(uuidString: profile.dataStoreUUID) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
        }
        return config
    }
}
```

**Note on `WKWebsiteDataStore(forIdentifier:)`:** this API is available on macOS 14 and later. If the deployment target is macOS 13, this call is guarded by `#available` or the deployment target is bumped to macOS 14. Plan A assumes macOS 14+ deployment; bump the target in the Xcode project's General tab if it is currently 13.

- [ ] **Step 10.2: Set deployment target to macOS 14**

In Xcode, select the `View` project, select the `View` target, on the `General` tab set `Minimum Deployments` > `macOS` to `14.0`.

- [ ] **Step 10.3: Build and run**

In Xcode, press Cmd-R.
Expected: App launches, a window opens, `example.com` loads inside it. Console log has no errors.

- [ ] **Step 10.4: Verify data directory was created on disk**

Run: `ls -la ~/Library/Application\ Support/View/`
Expected: Contains `Local State.toml` and a `Profiles/` directory. Inside `Profiles/Default/` there should be `settings.toml`, `view.sqlite` (plus `-shm` and `-wal` companion files), and a `WebData/` directory populated by WKWebView.

- [ ] **Step 10.5: Verify the `Local State.toml` content**

Run: `cat ~/Library/Application\ Support/View/Local\ State.toml`
Expected: Well-formed TOML with `active_profile = "Default"` and one profile entry containing a valid UUID under `data_store_uuid`.

- [ ] **Step 10.6: Verify the `settings.toml` content**

Run: `cat ~/Library/Application\ Support/View/Profiles/Default/settings.toml`
Expected: Contains `[view]`, `[startup]`, and `[vim]` sections with default values.

- [ ] **Step 10.7: Verify the SQLite schema**

Run: `sqlite3 ~/Library/Application\ Support/View/Profiles/Default/view.sqlite ".schema"`
Expected: Shows `sessions`, `windows`, `tabs`, and `grdb_migrations` tables.

- [ ] **Step 10.8: Commit**

```bash
git add View/AppDelegate.swift View.xcodeproj
git commit -m "Wire AppDelegate to bootstrap profile and open browser window"
```

---

## Task 11: Verify Global Zoom Preference Takes Effect

- [ ] **Step 11.1: Quit the app and edit settings.toml**

Run: `pkill -x View 2>/dev/null; sleep 1`
Then edit the zoom in the settings file:

Run: `sed -i '' 's/zoom = 1.0/zoom = 1.75/' ~/Library/Application\ Support/View/Profiles/Default/settings.toml`

Run: `cat ~/Library/Application\ Support/View/Profiles/Default/settings.toml`
Expected: `zoom = 1.75` is present.

- [ ] **Step 11.2: Relaunch and verify**

Launch the app from Xcode (Cmd-R). Observe that the `example.com` page is rendered at 1.75x zoom (visibly larger text).

- [ ] **Step 11.3: Reset zoom**

Quit the app. Restore the settings:

Run: `sed -i '' 's/zoom = 1.75/zoom = 1.0/' ~/Library/Application\ Support/View/Profiles/Default/settings.toml`

---

## Task 12: Verify Profile Data Store Persistence

This confirms that cookies written by the WKWebView survive across relaunches and are stored in the profile's `WebData` directory rather than the system default.

- [ ] **Step 12.1: Check the `WebData` directory is populated**

Run: `find ~/Library/Application\ Support/View/Profiles/Default/WebData -type f | head`
Expected: Several files exist (cookies, caches, etc.). This proves WKWebView is writing to the profile directory, not the system default location (`~/Library/WebKit/...`).

- [ ] **Step 12.2: (Optional) Verify the default store is not used**

Run: `ls ~/Library/WebKit/io.protoss.view 2>&1`
Expected: Directory does not exist, or if it does, it contains no application data. The profile-scoped store is isolated from the default location.

---

## Done Criteria for Plan A

All of the following must be true:

1. `swift test --package-path Packages/ViewCore` passes with zero failures.
2. The app launches from Xcode, displays one window containing one WKWebView loading `example.com`.
3. `~/Library/Application Support/View/Local State.toml` exists and round-trips through the app.
4. `~/Library/Application Support/View/Profiles/Default/settings.toml` exists with defaults.
5. `~/Library/Application Support/View/Profiles/Default/view.sqlite` exists with the three-table schema.
6. `~/Library/Application Support/View/Profiles/Default/WebData/` is populated by WKWebView (confirming profile data store isolation).
7. Editing `zoom` in `settings.toml` and relaunching the app visibly changes the page zoom.
8. Git history shows one commit per task, plus the bootstrap commits that preceded the plan.

What is **not** done and is deferred to later plans: multi-tab, multi-window, session restore, Vim keybindings, tab sidebar, error pages, crash placeholder, Debug menu, observability indicator, os_log wiring, manual acceptance checklist items 1 through 10 in the spec.
