# Plan B: Multi-Tab, Multi-Window, Session Restore

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Plan A walking skeleton into a real multi-tab, multi-window browser with session persistence. After Plan B the user can open multiple windows, each with a vertical tab sidebar, create and close tabs, reorder them, and have every window + tab restored across app launches. Lazy restoration keeps startup cheap even with many tabs.

**Architecture:**
- App-layer `Tab` owns a URL, title, optional `WKWebView` (nil means unloaded), and an optional persistence id.
- `BrowserWindowController` owns an array of `Tab`s, a `TabSidebarView` (left), a `WebContainerView` (right), and the index of the currently active tab.
- `WindowManager` owns all `BrowserWindowController`s, handles Cmd-N, tracks z_order.
- `RestorationQueue` is a serial worker that promotes unloaded tabs one at a time, triggered by each previous tab's `didFinish`.
- `SessionController` glues events to persistence: it listens to tab/window mutations and writes through `SessionStore` immediately (no debounce, no timer). On launch it reads the latest session and asks `WindowManager` to rebuild it.
- `SessionStore` (already created in Plan A with schema only) gets CRUD methods: save/load a full session snapshot, start a new session, archive the active session.

**Tech Stack:** Swift 5.9+, AppKit (NSTableView, NSWindow, NSViewController), WebKit, GRDB.swift, XCTest.

**Spec reference:** `docs/superpowers/specs/2026-04-15-view-browser-design.md`

**Important context from Plan A (already in place, do not re-design):**
- `@main` entry is `View/ViewApp.swift`; `AppDelegate` is not `@main`.
- `View/MainMenuBuilder.swift` programmatically builds the menu bar.
- App Sandbox is disabled.
- `WKWebsiteDataStore(forIdentifier:)` is already threaded through in `AppDelegate.makeConfiguration`.
- `SessionStore` already exists with a v1 schema but has no CRUD methods yet.
- Spec section 4.5 originally said "debounced at 1s"; Plan B supersedes that with **pure event-driven writes** using end-of-interaction AppKit notifications (`NSWindowDidEndLiveResize`, `NSWindowDidMove`). No debounce, no timer.

**Design decisions (confirmed during brainstorming):**
- TabSidebar implementation: pure AppKit `NSTableView`, no SwiftUI.
- Cmd-N opens a new window with one blank tab (`about:blank`).
- Cmd-T creates an `about:blank` tab. No configurable "new tab page" in MVP.
- On restore, the front-most window is determined by lowest `z_order`.
- Session saves are **event-driven**, one write per discrete event. Use `NSWindowDidEndLiveResize` / `NSWindowDidMove` so geometry saves are one-shot per interaction.
- Restoration is lazy: every non-active tab starts as unloaded (no WKWebView). A global serial restoration queue promotes them one at a time triggered by the previous tab's `didFinish`. User clicks on an unloaded tab promote out-of-order.
- MVP sidebar shows tab title only, no favicon (persisting favicons is deferred).

---

## File Structure

```
Packages/ViewCore/
└── Sources/ViewCore/
    ├── SessionStore.swift              (modified: add CRUD)
    └── SessionSnapshot.swift           (new: plain data types for DB rows + snapshot aggregate)
└── Tests/ViewCoreTests/
    ├── SessionStoreTests.swift         (extended: CRUD tests)
    └── SessionSnapshotTests.swift      (new)

View/
├── Tab.swift                           (new: app-layer tab model)
├── TabSidebarView.swift                (new: NSTableView-based vertical tab list)
├── WebContainerView.swift              (new: NSView hosting the active tab's WKWebView)
├── BrowserWindowController.swift       (rewritten: owns tabs, sidebar, container)
├── WindowManager.swift                 (new: tracks all windows, handles new window)
├── RestorationQueue.swift              (new: serial promotion worker)
├── SessionController.swift             (new: bridge events ↔ SessionStore)
├── AppDelegate.swift                   (slimmed: delegates to WindowManager + SessionController)
└── MainMenuBuilder.swift               (extended: add Cmd-N, Cmd-T, Cmd-W actions)
```

**Responsibilities:**
- **`SessionSnapshot`**: Codable-ish plain structs: `SessionRow`, `WindowRow`, `TabRow`, plus a `SessionSnapshot` aggregate that holds one session and all its windows+tabs in memory.
- **`SessionStore` (extended)**: `loadLatestSnapshot() throws -> SessionSnapshot?`, `beginNewSession() throws -> Int64`, `archiveActiveSession() throws`, `saveWindow(_:sessionID:)`, `saveTab(_:windowID:)`, `deleteWindow(id:)`, `deleteTab(id:)`, `updateTab(...)` etc. All methods are synchronous and thread-safe via GRDB's `write { db in ... }` blocks.
- **`Tab`** (app layer): class holding `persistenceID: Int64?`, `url: URL`, `title: String?`, `webView: WKWebView?`, `position: Int`, `onStateChange: (() -> Void)?`. `isLoaded` is `webView != nil`.
- **`TabSidebarView`**: `NSTableView` with one column, custom cell view showing the title. Selection drives `onSelectTab(index)`. Close button per row (hover-revealed) drives `onCloseTab(index)`. Drag reorder drives `onReorderTab(from:to:)`.
- **`WebContainerView`**: `NSView` that holds at most one `WKWebView` child filling its bounds. `setWebView(_:)` swaps the child.
- **`BrowserWindowController`**: owns `tabs: [Tab]`, `activeTabIndex: Int`, constructs a split view with `TabSidebarView` on the left and `WebContainerView` on the right, wires sidebar callbacks, reacts to `activeTabIndex` changes by calling `webContainer.setWebView(tabs[activeTabIndex].webView)` (creating the webView on demand if the active tab is unloaded).
- **`WindowManager`**: singleton-ish class held by AppDelegate. Owns `controllers: [BrowserWindowController]`. `openNewWindow(initialURL:)`, `openRestoredWindow(from: WindowRow, tabs: [TabRow])`, `closeWindow(_:)`. Observes `NSWindow.didBecomeKeyNotification` to update z_order.
- **`RestorationQueue`**: a worker that holds `pendingTabs: [Tab]` and promotes them one at a time. Each promotion creates the `WKWebView`, calls `load`, and registers a one-shot `didFinish` observer to trigger the next. User clicks on an unloaded tab cause `promoteNow(_:)` which removes from queue and promotes immediately.
- **`SessionController`**: owns a `SessionStore` reference and listens to window/tab lifecycle notifications (published by `WindowManager` and `BrowserWindowController`). Each notification triggers a synchronous write. On launch, reads the latest snapshot and hands it to `WindowManager` for restoration.

---

## Task 1: Extend `SessionStore` with CRUD for Sessions

**Files:**
- Create: `Packages/ViewCore/Sources/ViewCore/SessionSnapshot.swift`
- Modify: `Packages/ViewCore/Sources/ViewCore/SessionStore.swift`
- Create: `Packages/ViewCore/Tests/ViewCoreTests/SessionSnapshotTests.swift`
- Modify: `Packages/ViewCore/Tests/ViewCoreTests/SessionStoreTests.swift`

The goal is to add typed row structs and CRUD methods so Plan B's `SessionController` can save/restore.

- [ ] **Step 1.1: Write `SessionSnapshot.swift`**

```swift
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

    public init(id: Int64? = nil, createdAt: String, closedAt: String? = nil, label: String? = nil) {
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
```

- [ ] **Step 1.2: Extend `SessionStore` with CRUD**

Add these methods to the existing `SessionStore` class (do not remove or rename existing code):

```swift
// MARK: - Session lifecycle

public func beginNewSession() throws -> Int64 {
    try writer.write { db in
        var row = SessionRow(createdAt: ISO8601DateFormatter().string(from: Date()))
        try row.insert(db)
        return row.id!
    }
}

public func archiveActiveSession() throws {
    try writer.write { db in
        try db.execute(
            sql: "UPDATE sessions SET closed_at = ? WHERE closed_at IS NULL",
            arguments: [ISO8601DateFormatter().string(from: Date())]
        )
    }
}

public func loadLatestSnapshot() throws -> SessionSnapshot? {
    try reader.read { db in
        guard
            let session = try SessionRow
                .order(Column("created_at").desc)
                .fetchOne(db)
        else { return nil }

        let windows =
            try WindowRow
            .filter(Column("session_id") == session.id!)
            .order(Column("z_order"))
            .fetchAll(db)

        var combined: [(window: WindowRow, tabs: [TabRow])] = []
        for window in windows {
            let tabs =
                try TabRow
                .filter(Column("window_id") == window.id!)
                .order(Column("position"))
                .fetchAll(db)
            combined.append((window, tabs))
        }

        return SessionSnapshot(session: session, windowsWithTabs: combined)
    }
}

public func reopenSession(id: Int64) throws {
    try writer.write { db in
        try db.execute(
            sql: "UPDATE sessions SET closed_at = NULL WHERE id = ?",
            arguments: [id]
        )
    }
}

// MARK: - Window CRUD

@discardableResult
public func insertWindow(_ row: WindowRow) throws -> Int64 {
    try writer.write { db in
        var mutable = row
        try mutable.insert(db)
        return mutable.id!
    }
}

public func updateWindow(_ row: WindowRow) throws {
    try writer.write { db in
        try row.update(db)
    }
}

public func deleteWindow(id: Int64) throws {
    try writer.write { db in
        _ = try WindowRow.deleteOne(db, key: id)
    }
}

// MARK: - Tab CRUD

@discardableResult
public func insertTab(_ row: TabRow) throws -> Int64 {
    try writer.write { db in
        var mutable = row
        try mutable.insert(db)
        return mutable.id!
    }
}

public func updateTab(_ row: TabRow) throws {
    try writer.write { db in
        try row.update(db)
    }
}

public func deleteTab(id: Int64) throws {
    try writer.write { db in
        _ = try TabRow.deleteOne(db, key: id)
    }
}
```

- [ ] **Step 1.3: Write tests for CRUD**

Add these test methods to `SessionStoreTests.swift`:

```swift
func testBeginNewSessionInserts() throws {
    let store = try SessionStore(dbQueue: try DatabaseQueue())
    let id = try store.beginNewSession()
    XCTAssertGreaterThan(id, 0)

    try store.reader.read { db in
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NULL") ?? -1
        XCTAssertEqual(count, 1)
    }
}

func testArchiveActiveSession() throws {
    let store = try SessionStore(dbQueue: try DatabaseQueue())
    _ = try store.beginNewSession()
    try store.archiveActiveSession()

    try store.reader.read { db in
        let active = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NULL") ?? -1
        XCTAssertEqual(active, 0)
        let archived = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE closed_at IS NOT NULL") ?? -1
        XCTAssertEqual(archived, 1)
    }
}

func testRoundTripSnapshot() throws {
    let store = try SessionStore(dbQueue: try DatabaseQueue())
    let sessionId = try store.beginNewSession()

    let windowId = try store.insertWindow(
        WindowRow(sessionId: sessionId, frameX: 100, frameY: 200, frameW: 1280, frameH: 800, zOrder: 0)
    )

    _ = try store.insertTab(
        TabRow(windowId: windowId, url: "https://example.com", title: "Example", position: 0, isActive: true)
    )
    _ = try store.insertTab(
        TabRow(windowId: windowId, url: "https://news.ycombinator.com", title: "HN", position: 1, isActive: false)
    )

    let snapshot = try store.loadLatestSnapshot()
    XCTAssertNotNil(snapshot)
    XCTAssertEqual(snapshot?.session.id, sessionId)
    XCTAssertEqual(snapshot?.windowsWithTabs.count, 1)
    XCTAssertEqual(snapshot?.windowsWithTabs[0].tabs.count, 2)
    XCTAssertEqual(snapshot?.windowsWithTabs[0].tabs[0].url, "https://example.com")
    XCTAssertTrue(snapshot?.windowsWithTabs[0].tabs[0].isActive ?? false)
}

func testDeleteWindowCascadesToTabs() throws {
    let store = try SessionStore(dbQueue: try DatabaseQueue())
    let sessionId = try store.beginNewSession()
    let windowId = try store.insertWindow(
        WindowRow(sessionId: sessionId, frameX: 0, frameY: 0, frameW: 800, frameH: 600, zOrder: 0)
    )
    _ = try store.insertTab(
        TabRow(windowId: windowId, url: "https://a.com", title: nil, position: 0, isActive: true)
    )
    _ = try store.insertTab(
        TabRow(windowId: windowId, url: "https://b.com", title: nil, position: 1, isActive: false)
    )

    try store.deleteWindow(id: windowId)

    try store.reader.read { db in
        let tabCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tabs") ?? -1
        XCTAssertEqual(tabCount, 0)
    }
}
```

- [ ] **Step 1.4: Run tests**

Run: `make test-core`
Expected: All tests pass including the new ones.

- [ ] **Step 1.5: Format and commit**

Run: `make fmt && make fmt-check`
Then:
```bash
git add Packages/ViewCore
git commit -m "Add CRUD and snapshot load to SessionStore"
```

---

## Task 2: Create App-Layer `Tab` Model

**Files:**
- Create: `View/Tab.swift`

- [ ] **Step 2.1: Write `Tab.swift`**

```swift
import AppKit
import Foundation
import WebKit

final class Tab {
    var persistenceID: Int64?
    var url: URL
    var title: String?
    var webView: WKWebView?
    var position: Int

    var onTitleChange: ((Tab) -> Void)?
    var onNavigationFinish: ((Tab) -> Void)?

    var isLoaded: Bool { webView != nil }

    init(
        persistenceID: Int64? = nil,
        url: URL,
        title: String? = nil,
        position: Int
    ) {
        self.persistenceID = persistenceID
        self.url = url
        self.title = title
        self.webView = nil
        self.position = position
    }

    func adopt(webView: WKWebView) {
        self.webView = webView
    }

    func releaseWebView() {
        self.webView = nil
    }
}
```

- [ ] **Step 2.2: Build**

Run: `make fmt && make debug 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 2.3: Commit**

```bash
git add View/Tab.swift
git commit -m "Add Tab model with optional webView for lazy state"
```

---

## Task 3: Create `WebContainerView`

**Files:**
- Create: `View/WebContainerView.swift`

- [ ] **Step 3.1: Write `WebContainerView.swift`**

```swift
import AppKit
import WebKit

final class WebContainerView: NSView {
    private var currentWebView: WKWebView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setWebView(_ webView: WKWebView?) {
        if currentWebView === webView { return }
        currentWebView?.removeFromSuperview()
        currentWebView = webView

        guard let webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}
```

- [ ] **Step 3.2: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -5
git add View/WebContainerView.swift
git commit -m "Add WebContainerView that hosts at most one WKWebView"
```

---

## Task 4: Create `TabSidebarView`

A single-column `NSTableView` that renders tab titles, reports selection and close events. Drag-to-reorder is in MVP.

**Files:**
- Create: `View/TabSidebarView.swift`

- [ ] **Step 4.1: Write `TabSidebarView.swift`**

```swift
import AppKit

protocol TabSidebarViewDelegate: AnyObject {
    func sidebarDidSelectTab(at index: Int)
    func sidebarDidRequestCloseTab(at index: Int)
    func sidebarDidReorderTab(from source: Int, to destination: Int)
}

final class TabSidebarView: NSView {
    weak var delegate: TabSidebarViewDelegate?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var titles: [String] = []

    private let pasteboardType = NSPasteboard.PasteboardType("io.protoss.view.tabIndex")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.style = .sourceList
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.action = #selector(tableViewClicked)
        tableView.target = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([pasteboardType])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func reloadTitles(_ newTitles: [String], selectedIndex: Int) {
        titles = newTitles
        tableView.reloadData()
        if selectedIndex >= 0 && selectedIndex < newTitles.count {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
    }

    func updateTitle(at index: Int, to title: String) {
        guard index >= 0 && index < titles.count else { return }
        titles[index] = title
        tableView.reloadData(
            forRowIndexes: IndexSet(integer: index),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    @objc private func tableViewClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectTab(at: row)
    }
}

extension TabSidebarView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        titles.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TabCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)
        cell.textField?.stringValue = titles[row]
        return cell
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectTab(at: row)
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: pasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let item = info.draggingPasteboard.pasteboardItems?.first,
            let sourceString = item.string(forType: pasteboardType),
            let source = Int(sourceString)
        else { return false }
        let destination = source < row ? row - 1 : row
        delegate?.sidebarDidReorderTab(from: source, to: destination)
        return true
    }
}
```

Note: this MVP sidebar omits a per-row close button. Close is performed via Cmd-W from the menu bar (Plan A already wired `performClose:`). A close button in the row is deferred.

- [ ] **Step 4.2: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -5
git add View/TabSidebarView.swift
git commit -m "Add TabSidebarView (NSTableView with drag reorder)"
```

---

## Task 5: Rewrite `BrowserWindowController`

The new controller owns a tab array, a sidebar, and a container, and exposes the operations needed by `WindowManager` and `SessionController`.

**Files:**
- Modify: `View/BrowserWindowController.swift`

- [ ] **Step 5.1: Rewrite**

```swift
import AppKit
import WebKit

protocol BrowserWindowControllerDelegate: AnyObject {
    func browserWindow(_ controller: BrowserWindowController, didChangeTabs: Void)
    func browserWindow(
        _ controller: BrowserWindowController,
        needsWebViewFor tab: Tab
    ) -> WKWebView
    func browserWindow(
        _ controller: BrowserWindowController,
        didActivateTab tab: Tab
    )
}

final class BrowserWindowController: NSWindowController {
    weak var delegate: BrowserWindowControllerDelegate?
    var persistenceID: Int64?
    var zOrder: Int = 0

    private(set) var tabs: [Tab] = []
    private(set) var activeTabIndex: Int = -1

    private let sidebar = TabSidebarView()
    private let container = WebContainerView()
    private let splitView = NSSplitView()

    init(initialFrame: NSRect) {
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "View"
        super.init(window: window)
        setUpContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpContentView() {
        guard let contentView = window?.contentView else { return }

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        sidebar.delegate = self
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(container)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)

        contentView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
        splitView.setPosition(200, ofDividerAt: 0)
    }

    // MARK: - Tab management

    func addTab(_ tab: Tab, activate: Bool) {
        tabs.append(tab)
        tab.onTitleChange = { [weak self] updated in
            self?.refreshSidebar()
        }
        if activate {
            setActiveTabIndex(tabs.count - 1)
        }
        refreshSidebar()
        delegate?.browserWindow(self, didChangeTabs: ())
    }

    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs.remove(at: index)
        tab.webView?.removeFromSuperview()
        if tabs.isEmpty {
            activeTabIndex = -1
            container.setWebView(nil)
            window?.performClose(nil)
            return
        }
        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
        for (i, t) in tabs.enumerated() { t.position = i }
        refreshSidebar()
        activateCurrent()
        delegate?.browserWindow(self, didChangeTabs: ())
    }

    func reorderTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source) else { return }
        let moved = tabs.remove(at: source)
        let dest = min(destination, tabs.count)
        tabs.insert(moved, at: dest)
        for (i, t) in tabs.enumerated() { t.position = i }
        if activeTabIndex == source {
            activeTabIndex = dest
        } else if source < activeTabIndex && dest >= activeTabIndex {
            activeTabIndex -= 1
        } else if source > activeTabIndex && dest <= activeTabIndex {
            activeTabIndex += 1
        }
        refreshSidebar()
        delegate?.browserWindow(self, didChangeTabs: ())
    }

    func setActiveTabIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        activateCurrent()
        sidebar.reloadTitles(tabs.map { $0.title ?? $0.url.absoluteString }, selectedIndex: index)
    }

    private func activateCurrent() {
        guard tabs.indices.contains(activeTabIndex) else {
            container.setWebView(nil)
            return
        }
        let tab = tabs[activeTabIndex]
        if tab.webView == nil, let delegate {
            let webView = delegate.browserWindow(self, needsWebViewFor: tab)
            tab.adopt(webView: webView)
            webView.load(URLRequest(url: tab.url))
        }
        container.setWebView(tab.webView)
        delegate?.browserWindow(self, didActivateTab: tab)
    }

    private func refreshSidebar() {
        sidebar.reloadTitles(
            tabs.map { $0.title ?? $0.url.absoluteString },
            selectedIndex: activeTabIndex
        )
    }
}

extension BrowserWindowController: TabSidebarViewDelegate {
    func sidebarDidSelectTab(at index: Int) {
        setActiveTabIndex(index)
    }

    func sidebarDidRequestCloseTab(at index: Int) {
        removeTab(at: index)
    }

    func sidebarDidReorderTab(from source: Int, to destination: Int) {
        reorderTab(from: source, to: destination)
    }
}
```

- [ ] **Step 5.2: Build**

```bash
make fmt && make debug 2>&1 | tail -15
```

Note: `AppDelegate` will not yet compile because it uses the old `BrowserWindowController(webViewConfiguration:initialURL:zoom:)` init. Task 10 rewrites `AppDelegate`. For this task, update `AppDelegate` to a stub that keeps the app compiling but does nothing useful yet. See Step 5.3.

- [ ] **Step 5.3: Stub `AppDelegate` temporarily**

Replace the contents of `applicationDidFinishLaunching` with a TODO comment so the build passes:

```swift
func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Wired up in Plan B Task 10. Intentionally empty.
}
```

Remove the now-unused `browserController`, `profile`, `settings`, `sessionStore`, and `makeConfiguration` members and the `WebKit` import. Keep `applicationWillFinishLaunching` (main menu) and the `applicationSupports*` / `applicationShould*` methods.

- [ ] **Step 5.4: Build**

```bash
make fmt && make debug 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 5.5: Commit**

```bash
git add View/BrowserWindowController.swift View/AppDelegate.swift
git commit -m "Rewrite BrowserWindowController to own tabs, sidebar, container"
```

---

## Task 6: Create `WindowManager`

`WindowManager` owns all `BrowserWindowController` instances, provides methods to open/close windows, and maintains z_order by listening to key window notifications.

**Files:**
- Create: `View/WindowManager.swift`

- [ ] **Step 6.1: Write `WindowManager.swift`**

```swift
import AppKit
import ViewCore
import WebKit

protocol WindowManagerDelegate: AnyObject {
    func windowManager(_ manager: WindowManager, didOpenController controller: BrowserWindowController)
    func windowManager(_ manager: WindowManager, didCloseController controller: BrowserWindowController)
    func windowManagerZOrderDidChange(_ manager: WindowManager)
}

final class WindowManager: NSObject, BrowserWindowControllerDelegate {
    weak var delegate: WindowManagerDelegate?

    private(set) var controllers: [BrowserWindowController] = []
    private let webViewConfiguration: WKWebViewConfiguration
    private let defaultZoom: Double

    init(webViewConfiguration: WKWebViewConfiguration, defaultZoom: Double) {
        self.webViewConfiguration = webViewConfiguration
        self.defaultZoom = defaultZoom
        super.init()
    }

    func openNewWindow(initialURL: URL) -> BrowserWindowController {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let controller = BrowserWindowController(initialFrame: frame)
        controller.window?.center()
        controller.delegate = self
        controllers.append(controller)

        let tab = Tab(url: initialURL, title: nil, position: 0)
        controller.addTab(tab, activate: true)

        controller.showWindow(nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: controller.window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: controller.window
        )

        delegate?.windowManager(self, didOpenController: controller)
        return controller
    }

    func openRestoredWindow(
        at frame: NSRect,
        zOrder: Int,
        persistenceID: Int64,
        restoredTabs: [(persistenceID: Int64, url: URL, title: String?, isActive: Bool)]
    ) -> BrowserWindowController {
        let controller = BrowserWindowController(initialFrame: frame)
        controller.persistenceID = persistenceID
        controller.zOrder = zOrder
        controller.delegate = self
        controllers.append(controller)

        var activeIndex = 0
        for (i, restored) in restoredTabs.enumerated() {
            let tab = Tab(
                persistenceID: restored.persistenceID,
                url: restored.url,
                title: restored.title,
                position: i
            )
            controller.addTab(tab, activate: false)
            if restored.isActive { activeIndex = i }
        }
        if !restoredTabs.isEmpty {
            controller.setActiveTabIndex(activeIndex)
        }

        controller.showWindow(nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: controller.window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: controller.window
        )

        delegate?.windowManager(self, didOpenController: controller)
        return controller
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let remaining = controllers.filter { $0.window !== window }
        guard let front = controllers.first(where: { $0.window === window }) else { return }
        front.zOrder = 0
        for (i, c) in remaining.enumerated() {
            c.zOrder = i + 1
        }
        delegate?.windowManagerZOrderDidChange(self)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let index = controllers.firstIndex(where: { $0.window === window }) else { return }
        let controller = controllers.remove(at: index)
        NotificationCenter.default.removeObserver(self, name: nil, object: window)
        delegate?.windowManager(self, didCloseController: controller)
    }

    // MARK: - BrowserWindowControllerDelegate

    func browserWindow(_ controller: BrowserWindowController, didChangeTabs: Void) {
        // Forwarded via notification in Task 8 (SessionController).
    }

    func browserWindow(
        _ controller: BrowserWindowController,
        needsWebViewFor tab: Tab
    ) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        webView.pageZoom = CGFloat(defaultZoom)
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }

    func browserWindow(_ controller: BrowserWindowController, didActivateTab tab: Tab) {
        // Forwarded in Task 8.
    }
}
```

- [ ] **Step 6.2: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -10
git add View/WindowManager.swift
git commit -m "Add WindowManager for programmatic window lifecycle"
```

---

## Task 7: Create `RestorationQueue`

Serial worker that promotes unloaded tabs to loaded, one at a time, triggered by each previous tab's `didFinish`.

**Files:**
- Create: `View/RestorationQueue.swift`

- [ ] **Step 7.1: Write `RestorationQueue.swift`**

```swift
import AppKit
import WebKit

final class RestorationQueue: NSObject, WKNavigationDelegate {
    private var pending: [Tab] = []
    private weak var currentTab: Tab?
    private let webViewFactory: (Tab) -> WKWebView
    private let container: (Tab) -> WebContainerView?

    init(
        webViewFactory: @escaping (Tab) -> WKWebView,
        container: @escaping (Tab) -> WebContainerView?
    ) {
        self.webViewFactory = webViewFactory
        self.container = container
        super.init()
    }

    func enqueue(_ tabs: [Tab]) {
        pending.append(contentsOf: tabs.filter { !$0.isLoaded })
        if currentTab == nil { promoteNext() }
    }

    func promoteNow(_ tab: Tab) {
        pending.removeAll { $0 === tab }
        if !tab.isLoaded {
            load(tab: tab)
        }
    }

    private func promoteNext() {
        guard let next = pending.first else {
            currentTab = nil
            return
        }
        pending.removeFirst()
        load(tab: next)
    }

    private func load(tab: Tab) {
        currentTab = tab
        let webView = webViewFactory(tab)
        webView.navigationDelegate = self
        tab.adopt(webView: webView)
        webView.load(URLRequest(url: tab.url))
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.navigationDelegate = nil
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.navigationDelegate = nil
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        webView.navigationDelegate = nil
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }
}
```

Note: the `container` closure parameter is not used yet but is retained so Task 8 can wire it for status feedback if needed. If unused at Task 8, remove it then.

- [ ] **Step 7.2: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -5
git add View/RestorationQueue.swift
git commit -m "Add RestorationQueue for serial lazy tab promotion"
```

---

## Task 8: Create `SessionController`

Glues window/tab lifecycle to `SessionStore`. Owns the `WindowManager` and the `RestorationQueue`. On launch it reads the latest snapshot and rebuilds windows (or starts fresh). On any lifecycle event it writes through to `SessionStore` immediately.

**Files:**
- Create: `View/SessionController.swift`

- [ ] **Step 8.1: Write `SessionController.swift`**

```swift
import AppKit
import ViewCore
import WebKit

final class SessionController: NSObject {
    private let sessionStore: SessionStore
    private let settings: Settings
    private let windowManager: WindowManager
    private var restorationQueue: RestorationQueue!

    private var activeSessionID: Int64 = 0

    init(
        sessionStore: SessionStore,
        settings: Settings,
        webViewConfiguration: WKWebViewConfiguration
    ) {
        self.sessionStore = sessionStore
        self.settings = settings
        self.windowManager = WindowManager(
            webViewConfiguration: webViewConfiguration,
            defaultZoom: settings.view.zoom
        )
        super.init()
        self.windowManager.delegate = self
        self.restorationQueue = RestorationQueue(
            webViewFactory: { [weak self] _ in
                guard let self else { fatalError() }
                let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
                webView.pageZoom = CGFloat(self.settings.view.zoom)
                return webView
            },
            container: { _ in nil }
        )
    }

    func start() throws {
        let snapshot = try sessionStore.loadLatestSnapshot()

        switch settings.startup.mode {
        case .resume:
            if let snapshot, !snapshot.windowsWithTabs.isEmpty {
                try sessionStore.reopenSession(id: snapshot.session.id!)
                activeSessionID = snapshot.session.id!
                try restoreSnapshot(snapshot)
                return
            }
            try startFreshSession()
        case .blank:
            try startFreshSession()
        }
    }

    private func startFreshSession() throws {
        activeSessionID = try sessionStore.beginNewSession()
        let controller = windowManager.openNewWindow(
            initialURL: URL(string: "about:blank")!
        )
        try persistNewWindow(controller)
        if let firstTab = controller.tabs.first {
            try persistNewTab(firstTab, in: controller)
        }
    }

    private func restoreSnapshot(_ snapshot: SessionSnapshot) throws {
        var pendingUnloaded: [Tab] = []

        for entry in snapshot.windowsWithTabs {
            let frame = NSRect(
                x: entry.window.frameX,
                y: entry.window.frameY,
                width: entry.window.frameW,
                height: entry.window.frameH
            )
            let restoredTabs: [(persistenceID: Int64, url: URL, title: String?, isActive: Bool)] =
                entry.tabs.compactMap { row in
                    guard let id = row.id, let url = URL(string: row.url) else { return nil }
                    return (id, url, row.title, row.isActive)
                }
            let controller = windowManager.openRestoredWindow(
                at: frame,
                zOrder: entry.window.zOrder,
                persistenceID: entry.window.id!,
                restoredTabs: restoredTabs
            )
            for tab in controller.tabs where tab.webView == nil && tab !== controller.tabs[controller.activeTabIndex] {
                pendingUnloaded.append(tab)
            }
        }

        restorationQueue.enqueue(pendingUnloaded)
    }

    // MARK: - Persistence helpers

    private func persistNewWindow(_ controller: BrowserWindowController) throws {
        guard let window = controller.window else { return }
        let frame = window.frame
        let row = WindowRow(
            sessionId: activeSessionID,
            frameX: Double(frame.origin.x),
            frameY: Double(frame.origin.y),
            frameW: Double(frame.size.width),
            frameH: Double(frame.size.height),
            zOrder: controller.zOrder
        )
        let id = try sessionStore.insertWindow(row)
        controller.persistenceID = id
    }

    private func persistNewTab(_ tab: Tab, in controller: BrowserWindowController) throws {
        guard let windowID = controller.persistenceID else { return }
        let row = TabRow(
            windowId: windowID,
            url: tab.url.absoluteString,
            title: tab.title,
            position: tab.position,
            isActive: controller.tabs[controller.activeTabIndex] === tab
        )
        let id = try sessionStore.insertTab(row)
        tab.persistenceID = id
    }

    func quit() {
        try? sessionStore.archiveActiveSession()
    }

    var manager: WindowManager { windowManager }
}

extension SessionController: WindowManagerDelegate {
    func windowManager(
        _ manager: WindowManager,
        didOpenController controller: BrowserWindowController
    ) {
        // New-window persistence is handled by the caller (startFreshSession / restoreSnapshot).
        // This hook exists so Plan C can observe new windows.
    }

    func windowManager(
        _ manager: WindowManager,
        didCloseController controller: BrowserWindowController
    ) {
        guard let id = controller.persistenceID else { return }
        try? sessionStore.deleteWindow(id: id)
    }

    func windowManagerZOrderDidChange(_ manager: WindowManager) {
        for controller in manager.controllers {
            guard let id = controller.persistenceID, let window = controller.window else { continue }
            let row = WindowRow(
                id: id,
                sessionId: activeSessionID,
                frameX: Double(window.frame.origin.x),
                frameY: Double(window.frame.origin.y),
                frameW: Double(window.frame.size.width),
                frameH: Double(window.frame.size.height),
                zOrder: controller.zOrder
            )
            try? sessionStore.updateWindow(row)
        }
    }
}
```

**Note on write cadence:** this file implements the "pure event-driven" policy. There is no timer, no debounce. End-of-interaction notifications for geometry (`NSWindowDidEndLiveResize`, `NSWindowDidMove`) are wired in Task 9, which adds them as `NotificationCenter` observers that call through to `SessionStore.updateWindow`.

- [ ] **Step 8.2: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -15
git add View/SessionController.swift
git commit -m "Add SessionController bridging lifecycle events to SessionStore"
```

---

## Task 9: Wire Event-Driven Persistence

Add `NotificationCenter` observers for end-of-interaction geometry events, tab changes, and navigation finishes.

**Files:**
- Modify: `View/SessionController.swift`
- Modify: `View/BrowserWindowController.swift`
- Modify: `View/Tab.swift`

- [ ] **Step 9.1: Observe window geometry in `SessionController`**

In `SessionController.init`, after `self.windowManager.delegate = self`, register for `NSWindow.didEndLiveResizeNotification` and `NSWindow.didMoveNotification` globally:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(windowGeometryChanged(_:)),
    name: NSWindow.didEndLiveResizeNotification,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(windowGeometryChanged(_:)),
    name: NSWindow.didMoveNotification,
    object: nil
)
```

Add the handler:

```swift
@objc private func windowGeometryChanged(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    guard let controller = windowManager.controllers.first(where: { $0.window === window }) else {
        return
    }
    guard let id = controller.persistenceID else { return }
    let frame = window.frame
    let row = WindowRow(
        id: id,
        sessionId: activeSessionID,
        frameX: Double(frame.origin.x),
        frameY: Double(frame.origin.y),
        frameW: Double(frame.size.width),
        frameH: Double(frame.size.height),
        zOrder: controller.zOrder
    )
    try? sessionStore.updateWindow(row)
}
```

- [ ] **Step 9.2: Persist tab mutations**

Replace the empty `browserWindow(_:didChangeTabs:)` implementation in `SessionController` with one that syncs the full tab list for that window:

```swift
func browserWindow(_ controller: BrowserWindowController, didChangeTabs: Void) {
    // Not called via the delegate anymore — WindowManager forwards this through.
}
```

Instead of a delegate bounce, have `BrowserWindowController` post a notification whenever its tab list changes. Add this to `BrowserWindowController`:

```swift
static let tabsDidChangeNotification = Notification.Name("BrowserWindowController.tabsDidChange")

private func postTabsDidChange() {
    NotificationCenter.default.post(name: Self.tabsDidChangeNotification, object: self)
}
```

Call `postTabsDidChange()` at the end of `addTab`, `removeTab`, `reorderTab`, and in `setActiveTabIndex`.

In `SessionController.init`, observe it:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(tabsDidChange(_:)),
    name: BrowserWindowController.tabsDidChangeNotification,
    object: nil
)
```

Handler: reconciles the window's tab array with the database by upserting every tab and deleting any that no longer exist. Simplest correct approach is:

```swift
@objc private func tabsDidChange(_ notification: Notification) {
    guard let controller = notification.object as? BrowserWindowController else { return }
    guard let windowID = controller.persistenceID else { return }

    // Load existing tab rows for this window
    let existing: [TabRow] = (try? sessionStore.writer.read { db in
        try TabRow.filter(Column("window_id") == windowID).fetchAll(db)
    }) ?? []

    let currentIDs = Set(controller.tabs.compactMap { $0.persistenceID })

    // Delete removed rows
    for row in existing where !currentIDs.contains(row.id!) {
        try? sessionStore.deleteTab(id: row.id!)
    }

    // Upsert current tabs
    for (i, tab) in controller.tabs.enumerated() {
        let isActive = i == controller.activeTabIndex
        if let id = tab.persistenceID {
            let row = TabRow(
                id: id,
                windowId: windowID,
                url: tab.url.absoluteString,
                title: tab.title,
                position: i,
                isActive: isActive
            )
            try? sessionStore.updateTab(row)
        } else {
            let row = TabRow(
                windowId: windowID,
                url: tab.url.absoluteString,
                title: tab.title,
                position: i,
                isActive: isActive
            )
            if let newID = try? sessionStore.insertTab(row) {
                tab.persistenceID = newID
            }
        }
    }
}
```

- [ ] **Step 9.3: Persist title and URL changes after navigation**

Add a `WKNavigationDelegate` handler that updates `tab.title` and `tab.url` when a page finishes loading, and posts `tabsDidChange` so the sidebar redraws and SQLite updates.

Create `View/BrowserNavigationObserver.swift`:

```swift
import AppKit
import WebKit

final class BrowserNavigationObserver: NSObject, WKNavigationDelegate {
    weak var tab: Tab?
    weak var owner: BrowserWindowController?

    init(tab: Tab, owner: BrowserWindowController) {
        self.tab = tab
        self.owner = owner
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab, let owner else { return }
        if let url = webView.url { tab.url = url }
        tab.title = webView.title
        owner.refreshAfterNavigation(tab: tab)
    }
}
```

Add a public `refreshAfterNavigation(tab:)` method to `BrowserWindowController` that refreshes the sidebar and posts the notification:

```swift
func refreshAfterNavigation(tab: Tab) {
    refreshSidebar()
    NotificationCenter.default.post(name: Self.tabsDidChangeNotification, object: self)
}
```

When `activateCurrent()` creates a new WebView for a tab, attach a `BrowserNavigationObserver` as its `navigationDelegate`. Store the observer strongly on `Tab` so it isn't deallocated — add `var navigationObserver: NSObject?` to `Tab`.

Important: `BrowserNavigationObserver` must not conflict with `RestorationQueue`'s own navigation delegate. Either (a) the restoration queue hands ownership back when its wait is over (swap the delegate from the queue to the observer in the queue's `didFinish`), or (b) restoration queue and observer are the same object with two roles. For simplicity pick (a): when `RestorationQueue`'s `didFinish` fires, replace the WebView's delegate with a `BrowserNavigationObserver`.

Update `RestorationQueue.webView(_:didFinish:)`:

```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let tab = currentTab, let owner = ownerLookup?(tab) else {
        promoteNext()
        return
    }
    tab.title = webView.title
    if let url = webView.url { tab.url = url }
    let observer = BrowserNavigationObserver(tab: tab, owner: owner)
    tab.navigationObserver = observer
    webView.navigationDelegate = observer
    owner.refreshAfterNavigation(tab: tab)
    DispatchQueue.main.async { [weak self] in
        self?.promoteNext()
    }
}
```

Add `var ownerLookup: ((Tab) -> BrowserWindowController?)?` to `RestorationQueue` and set it from `SessionController`.

- [ ] **Step 9.4: Build and commit**

```bash
make fmt && make debug 2>&1 | tail -15
git add View
git commit -m "Wire event-driven persistence for tabs, geometry, navigation"
```

---

## Task 10: Rewrite `AppDelegate` to use `SessionController`

**Files:**
- Modify: `View/AppDelegate.swift`

- [ ] **Step 10.1: Rewrite**

```swift
import Cocoa
import ViewCore
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sessionController: SessionController?

    func applicationWillFinishLaunching(_ aNotification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            let paths = AppPaths.default
            let profileManager = ProfileManager(paths: paths)
            let profile = try profileManager.bootstrap()

            let settings = try Settings.loadOrCreate(at: paths.settingsFile(profileId: profile.id))
            let sessionStore = try SessionStore(
                fileURL: paths.sessionDatabase(profileId: profile.id))

            let configuration = Self.makeConfiguration(profile: profile)
            let controller = SessionController(
                sessionStore: sessionStore,
                settings: settings,
                webViewConfiguration: configuration
            )
            try controller.start()
            self.sessionController = controller
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "View failed to launch"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        sessionController?.quit()
    }

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

- [ ] **Step 10.2: Build**

```bash
make fmt && make debug 2>&1 | tail -10
```

- [ ] **Step 10.3: Commit**

```bash
git add View/AppDelegate.swift
git commit -m "Route AppDelegate through SessionController"
```

---

## Task 11: Add Cmd-N and Cmd-T Menu Items

**Files:**
- Modify: `View/MainMenuBuilder.swift`
- Modify: `View/AppDelegate.swift`
- Modify: `View/BrowserWindowController.swift`

- [ ] **Step 11.1: Add menu items**

In `MainMenuBuilder.makeFileMenu()`, prepend two items:

```swift
let newWindow = menu.addItem(
    withTitle: "New Window",
    action: Selector(("newDocument:")),
    keyEquivalent: "n"
)
let newTab = menu.addItem(
    withTitle: "New Tab",
    action: Selector(("newTab:")),
    keyEquivalent: "t"
)
menu.addItem(.separator())
```

The default `#selector(NSDocumentController.newDocument(_:))` won't route to us without a document architecture. Instead, use responder chain with custom selectors. Add to `AppDelegate`:

```swift
@IBAction func newDocument(_ sender: Any?) {
    sessionController?.manager.openNewWindow(
        initialURL: URL(string: "about:blank")!
    )
}
```

And to `BrowserWindowController`:

```swift
@IBAction func newTab(_ sender: Any?) {
    let tab = Tab(url: URL(string: "about:blank")!, position: tabs.count)
    addTab(tab, activate: true)
}
```

- [ ] **Step 11.2: Build and test manually**

```bash
make fmt && make debug 2>&1 | tail -5
pkill -x View 2>/dev/null || true
.build/Build/Products/Debug/View.app/Contents/MacOS/View &
sleep 2
# Manually: Cmd-T opens a new blank tab, Cmd-N opens a new window.
# Close and relaunch to verify session restore.
```

- [ ] **Step 11.3: Commit**

```bash
git add View/MainMenuBuilder.swift View/AppDelegate.swift View/BrowserWindowController.swift
git commit -m "Add Cmd-N and Cmd-T for new window and new tab"
```

---

## Task 12: Manual Acceptance

- [ ] **Step 12.1: Clean slate**

```bash
pkill -x View 2>/dev/null || true
rm -rf ~/Library/Application\ Support/View
```

- [ ] **Step 12.2: First launch**

```bash
.build/Build/Products/Debug/View.app/Contents/MacOS/View &
sleep 2
```
Expected: one window opens with one `about:blank` tab in the sidebar.

- [ ] **Step 12.3: Multi-tab**

In the app: press Cmd-T three times. Type a URL is not yet supported in MVP, so manually open each new tab's URL by... Plan B does not include an address bar. The three new tabs will all be `about:blank`. Verify the sidebar shows four rows and selecting each row swaps the container.

- [ ] **Step 12.4: Multi-window**

Press Cmd-N. A second window appears with its own sidebar containing one `about:blank` tab.

- [ ] **Step 12.5: Reorder**

Drag a row in the sidebar to a different position. Verify the visual order changes and the active tab stays highlighted.

- [ ] **Step 12.6: Persistence**

Quit the app (Cmd-Q). Inspect the database:

```bash
sqlite3 ~/Library/Application\ Support/View/Profiles/Default/view.sqlite \
  "SELECT id, closed_at FROM sessions; SELECT id, session_id, z_order FROM windows; SELECT id, window_id, url, position, is_active FROM tabs;"
```
Expected: one archived session, two windows, five tabs total (4 + 1), positions and is_active flags correct.

- [ ] **Step 12.7: Restore**

Relaunch the app:

```bash
.build/Build/Products/Debug/View.app/Contents/MacOS/View &
sleep 3
```
Expected: both windows reappear with the same tab counts and sidebar contents. The previously active tabs are selected.

- [ ] **Step 12.8: Startup mode blank**

Quit, edit `settings.toml` to `mode = "blank"`, relaunch. A single window with one blank tab appears. Quit. Edit `settings.toml` back to `mode = "resume"`. The previously-active session's blank-mode new session is in the DB now; restoring should pick the most recent session (the blank one, which has just that one window). This is spec-correct behavior.

- [ ] **Step 12.9: Geometry persistence**

Quit, relaunch, resize and move a window. Quit. Relaunch. The window should reopen at the same frame.

---

## Done Criteria for Plan B

1. `make test-core` passes with the extended SessionStore tests.
2. `make debug` succeeds.
3. The app opens with one window, supports Cmd-T, Cmd-N, tab selection, drag reorder, and Cmd-W to close.
4. Session persists across quit/relaunch (Tasks 12.2 through 12.9).
5. Lazy restoration: on a multi-tab session, only the active tabs have WebViews immediately; non-active tabs promote one at a time on their predecessors' `didFinish`.
6. No session-store timer or debounce code exists; writes are purely event-driven.
7. All Plan A tests still pass.

---

## Out of Scope for Plan B (Deferred to Later Plans)

- Vim keybindings (Plan C).
- Address bar / URL input UI.
- Favicon display in sidebar.
- Close button per sidebar row (close via Cmd-W only).
- Navigation controls (back/forward/reload buttons).
- Page crash placeholder UI.
- Error page UI for navigation failures.
- Observability / Debug menu.
- Tab context menu (close others, close to the right, duplicate, etc.).
- Tab drag between windows.
- Restoring forward/back history per tab.
