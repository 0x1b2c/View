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
