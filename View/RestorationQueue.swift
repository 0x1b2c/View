import AppKit
import WebKit

final class RestorationQueue: NSObject, WKNavigationDelegate {
    private var pending: [Tab] = []
    private weak var currentTab: Tab?
    private let webViewFactory: (Tab) -> WKWebView
    private let container: (Tab) -> WebContainerView?

    var ownerLookup: ((Tab) -> BrowserWindowController?)?

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
        if let tab = currentTab {
            if let url = webView.url { tab.url = url }
            tab.title = webView.title
            if let owner = ownerLookup?(tab) {
                let observer = BrowserNavigationObserver(tab: tab, owner: owner)
                tab.navigationObserver = observer
                webView.navigationDelegate = observer
                owner.refreshAfterNavigation(tab: tab)
            } else {
                webView.navigationDelegate = nil
            }
        } else {
            webView.navigationDelegate = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let tab = currentTab, let owner = ownerLookup?(tab) {
            let observer = BrowserNavigationObserver(tab: tab, owner: owner)
            tab.navigationObserver = observer
            webView.navigationDelegate = observer
        } else {
            webView.navigationDelegate = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if let tab = currentTab, let owner = ownerLookup?(tab) {
            let observer = BrowserNavigationObserver(tab: tab, owner: owner)
            tab.navigationObserver = observer
            webView.navigationDelegate = observer
        } else {
            webView.navigationDelegate = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.promoteNext()
        }
    }
}
