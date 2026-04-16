import AppKit
import ViewCore
import WebKit

protocol WindowManagerDelegate: AnyObject {
    func windowManager(
        _ manager: WindowManager,
        didOpenController controller: BrowserWindowController
    )
    func windowManager(
        _ manager: WindowManager,
        didCloseController controller: BrowserWindowController
    )
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

    @discardableResult
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

    @discardableResult
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

        controller.beginRestoring()
        var activeIndex = 0
        for (i, restored) in restoredTabs.enumerated() {
            let tab = Tab(
                persistenceID: restored.persistenceID,
                url: restored.url,
                title: restored.title,
                position: i
            )
            tab.skipHistoryOnNextFinish = true
            controller.addTab(tab, activate: false)
            if restored.isActive { activeIndex = i }
        }
        controller.endRestoring()
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
        guard let front = controllers.first(where: { $0.window === window }) else { return }
        let others = controllers.filter { $0 !== front }
        front.zOrder = 0
        for (i, c) in others.enumerated() {
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
        // Forwarded via notification in Task 10 (SessionController handler).
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
        // Forwarded in Task 10.
    }
}
