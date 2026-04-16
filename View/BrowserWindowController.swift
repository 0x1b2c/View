import AppKit
import ViewCore
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
    func browserWindow(
        _ controller: BrowserWindowController,
        suggestHistoryFor query: String
    ) -> [HistoryEntry]
}

final class BrowserWindowController: NSWindowController {
    static let tabsDidChangeNotification = Notification.Name(
        "BrowserWindowController.tabsDidChange")
    static let sidebarWidthDidChangeNotification = Notification.Name(
        "BrowserWindowController.sidebarWidthDidChange")
    static let sidebarWidthUserInfoKey = "width"

    weak var delegate: BrowserWindowControllerDelegate?
    var persistenceID: Int64?
    var zOrder: Int = 0

    private(set) var tabs: [Tab] = []
    private(set) var activeTabIndex: Int = -1

    private let sidebar = TabSidebarView()
    private let addressBar = AddressBarView()
    private let container = WebContainerView()
    private let splitView = NSSplitView()
    private let rightStack = NSStackView()

    private var progressObservation: NSKeyValueObservation?
    private var isRestoring = false
    private var suppressSidebarBroadcast = false

    init(initialFrame: NSRect) {
        let window = SilentBrowserWindow(
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(splitViewSubviewsDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitView
        )

        sidebar.delegate = self
        addressBar.delegate = self
        addressBar.suggestionProvider = { [weak self] query in
            self?.delegate?.browserWindow(self!, suggestHistoryFor: query) ?? []
        }

        rightStack.orientation = .vertical
        rightStack.spacing = 0
        rightStack.alignment = .width
        rightStack.distribution = .fill
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.addArrangedSubview(addressBar)
        rightStack.addArrangedSubview(container)

        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(rightStack)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)

        contentView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        splitView.setPosition(260, ofDividerAt: 0)
    }

    // MARK: - Address bar API

    func focusAddressBar() {
        _ = addressBar.focus()
    }

    @IBAction func newTab(_ sender: Any?) {
        let tab = Tab(url: URL(string: "about:blank")!, position: tabs.count)
        addTab(tab, activate: true)
        focusAddressBar()
    }

    @IBAction func openLocation(_ sender: Any?) {
        focusAddressBar()
    }

    @IBAction func viewShowNextTab(_ sender: Any?) {
        guard !tabs.isEmpty else { return }
        let next = (activeTabIndex + 1) % tabs.count
        setActiveTabIndex(next)
    }

    @IBAction func viewShowPreviousTab(_ sender: Any?) {
        guard !tabs.isEmpty else { return }
        let prev = (activeTabIndex - 1 + tabs.count) % tabs.count
        setActiveTabIndex(prev)
    }

    @IBAction func viewShowTabByIndex(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let index = item.tag
        guard tabs.indices.contains(index) else { return }
        setActiveTabIndex(index)
    }

    @IBAction func viewShowLastTab(_ sender: Any?) {
        guard !tabs.isEmpty else { return }
        setActiveTabIndex(tabs.count - 1)
    }

    @IBAction func viewGoBack(_ sender: Any?) {
        guard tabs.indices.contains(activeTabIndex) else { return }
        tabs[activeTabIndex].webView?.goBack()
    }

    @IBAction func viewGoForward(_ sender: Any?) {
        guard tabs.indices.contains(activeTabIndex) else { return }
        tabs[activeTabIndex].webView?.goForward()
    }

    @IBAction func viewReload(_ sender: Any?) {
        guard tabs.indices.contains(activeTabIndex) else { return }
        tabs[activeTabIndex].webView?.reload()
    }

    // MARK: - Tab management

    func addTab(_ tab: Tab, activate: Bool) {
        tabs.append(tab)
        tab.onTitleChange = { [weak self] _ in
            self?.refreshSidebar()
        }
        if tab.webView != nil {
            attachNavigationObserver(to: tab)
        }
        if activate {
            setActiveTabIndex(tabs.count - 1)
        }
        refreshSidebar()
        delegate?.browserWindow(self, didChangeTabs: ())
        postTabsDidChange()
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
        postTabsDidChange()
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
        postTabsDidChange()
    }

    func setActiveTabIndex(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        activateCurrent()
        refreshSidebar()
        postTabsDidChange()
    }

    private func activateCurrent() {
        guard tabs.indices.contains(activeTabIndex) else {
            container.setWebView(nil)
            addressBar.text = ""
            return
        }
        let tab = tabs[activeTabIndex]
        if tab.webView == nil, let delegate {
            let webView = delegate.browserWindow(self, needsWebViewFor: tab)
            tab.adopt(webView: webView)
            webView.load(URLRequest(url: tab.url))
            attachNavigationObserver(to: tab)
        }
        container.setWebView(tab.webView)
        addressBar.text = tab.url.absoluteString
        bindProgress(to: tab.webView)
        delegate?.browserWindow(self, didActivateTab: tab)
    }

    private func bindProgress(to webView: WKWebView?) {
        progressObservation = nil
        guard let webView else {
            addressBar.setProgress(0, animated: false)
            return
        }
        if webView.isLoading {
            addressBar.setProgress(webView.estimatedProgress, animated: false)
        } else {
            addressBar.setProgress(0, animated: false)
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) {
            [weak self] webView, _ in
            guard let self else { return }
            if webView.isLoading {
                self.addressBar.setProgress(webView.estimatedProgress, animated: true)
            } else {
                self.addressBar.setProgress(1, animated: true)
            }
        }
    }

    private func attachNavigationObserver(to tab: Tab) {
        guard let webView = tab.webView else { return }
        let observer = BrowserNavigationObserver(tab: tab, owner: self)
        tab.navigationObserver = observer
        webView.navigationDelegate = observer

        let ui = BrowserUIDelegate(owner: self)
        tab.uiDelegate = ui
        webView.uiDelegate = ui
    }

    func openBackgroundTab(
        with url: URL,
        configuration: WKWebViewConfiguration
    ) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.pageZoom = tabs.first?.webView?.pageZoom ?? 1.0
        webView.translatesAutoresizingMaskIntoConstraints = false

        let tab = Tab(url: url, position: tabs.count)
        tab.adopt(webView: webView)
        tabs.append(tab)
        tab.onTitleChange = { [weak self] _ in
            self?.refreshSidebar()
        }
        attachNavigationObserver(to: tab)
        refreshSidebar()
        delegate?.browserWindow(self, didChangeTabs: ())
        postTabsDidChange()
        return webView
    }

    func beginRestoring() {
        isRestoring = true
    }

    func endRestoring() {
        isRestoring = false
    }

    func applySidebarWidth(_ width: CGFloat) {
        suppressSidebarBroadcast = true
        splitView.setPosition(width, ofDividerAt: 0)
        suppressSidebarBroadcast = false
    }

    var currentSidebarWidth: CGFloat {
        sidebar.frame.width
    }

    private func postTabsDidChange() {
        guard !isRestoring else { return }
        NotificationCenter.default.post(name: Self.tabsDidChangeNotification, object: self)
    }

    func refreshAfterNavigation(tab: Tab) {
        refreshSidebar()
        postTabsDidChange()
    }

    private func refreshSidebar() {
        let items = tabs.map { tab in
            TabSidebarItem(
                title: tab.title ?? tab.url.absoluteString,
                favicon: tab.favicon
            )
        }
        sidebar.reloadItems(items, selectedIndex: activeTabIndex)
    }
}

extension BrowserWindowController {
    @objc fileprivate func splitViewSubviewsDidResize(_ notification: Notification) {
        guard !suppressSidebarBroadcast, !isRestoring else { return }
        let width = sidebar.frame.width
        guard width > 0 else { return }
        NotificationCenter.default.post(
            name: Self.sidebarWidthDidChangeNotification,
            object: self,
            userInfo: [Self.sidebarWidthUserInfoKey: width]
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

extension BrowserWindowController: AddressBarViewDelegate {
    func addressBar(_ addressBar: AddressBarView, didSubmitURL url: URL) {
        guard tabs.indices.contains(activeTabIndex) else { return }
        let tab = tabs[activeTabIndex]
        tab.url = url
        if let webView = tab.webView {
            webView.load(URLRequest(url: url))
        } else if let delegate {
            let webView = delegate.browserWindow(self, needsWebViewFor: tab)
            tab.adopt(webView: webView)
            container.setWebView(webView)
            webView.load(URLRequest(url: url))
            attachNavigationObserver(to: tab)
            bindProgress(to: webView)
        }
        addressBar.setProgress(0.1, animated: true)
        refreshSidebar()
        postTabsDidChange()
        window?.makeFirstResponder(tab.webView)
    }
}
