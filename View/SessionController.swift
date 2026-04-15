import AppKit
import GRDB
import ViewCore
import WebKit

final class SessionController: NSObject {
    private let sessionStore: SessionStore
    private let settings: Settings
    private let windowManager: WindowManager
    private var restorationQueue: RestorationQueue!

    private var activeSessionID: Int64 = 0
    private var isTerminating = false

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
                guard let self else { fatalError("SessionController deallocated") }
                let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
                webView.pageZoom = CGFloat(self.settings.view.zoom)
                return webView
            },
            container: { _ in nil }
        )
        self.restorationQueue.ownerLookup = { [weak self] tab in
            self?.findController(for: tab)
        }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tabsDidChange(_:)),
            name: BrowserWindowController.tabsDidChangeNotification,
            object: nil
        )
    }

    var manager: WindowManager { windowManager }

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

    func prepareForTermination() {
        isTerminating = true
    }

    func quit() {
        try? sessionStore.archiveActiveSession()
    }

    private func startFreshSession() throws {
        activeSessionID = try sessionStore.beginNewSession()
        _ = windowManager.openNewWindow(initialURL: URL(string: "about:blank")!)
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
            for (i, tab) in controller.tabs.enumerated()
            where tab.webView == nil && i != controller.activeTabIndex {
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
            isActive: controller.activeTabIndex >= 0
                && controller.tabs[controller.activeTabIndex] === tab
        )
        let id = try sessionStore.insertTab(row)
        tab.persistenceID = id
    }

    private func findController(for tab: Tab) -> BrowserWindowController? {
        windowManager.controllers.first { $0.tabs.contains { $0 === tab } }
    }

    @objc private func tabsDidChange(_ notification: Notification) {
        guard let controller = notification.object as? BrowserWindowController else { return }
        guard let windowID = controller.persistenceID else { return }
        let existing: [TabRow] =
            (try? sessionStore.reader.read { db in
                try TabRow.filter(Column("window_id") == windowID).fetchAll(db)
            }) ?? []
        let currentIDs = Set(controller.tabs.compactMap { $0.persistenceID })
        for row in existing where !currentIDs.contains(row.id!) {
            try? sessionStore.deleteTab(id: row.id!)
        }
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

    @objc private func windowGeometryChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard let controller = windowManager.controllers.first(where: { $0.window === window })
        else { return }
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
}

extension SessionController: WindowManagerDelegate {
    func windowManager(
        _ manager: WindowManager,
        didOpenController controller: BrowserWindowController
    ) {
        guard controller.persistenceID == nil else { return }
        try? persistNewWindow(controller)
        for tab in controller.tabs where tab.persistenceID == nil {
            try? persistNewTab(tab, in: controller)
        }
    }

    func windowManager(
        _ manager: WindowManager,
        didCloseController controller: BrowserWindowController
    ) {
        guard !isTerminating else { return }
        guard let id = controller.persistenceID else { return }
        try? sessionStore.deleteWindow(id: id)
    }

    func windowManagerZOrderDidChange(_ manager: WindowManager) {
        for controller in manager.controllers {
            guard let id = controller.persistenceID, let window = controller.window else {
                continue
            }
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
