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

        FaviconFetcher.shared.fetch(for: webView) { [weak tab, weak owner] image in
            guard let tab, let owner, let image else { return }
            tab.favicon = image
            owner.refreshAfterNavigation(tab: tab)
        }
    }

    func webView(
        _ webView: WKWebView,
        didSameDocumentNavigation navigation: WKNavigation!
    ) {
        guard let tab, let owner else { return }
        if let url = webView.url { tab.url = url }
        tab.title = webView.title
        owner.refreshAfterNavigation(tab: tab)
    }
}
