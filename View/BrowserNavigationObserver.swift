import AppKit
import WebKit

final class BrowserNavigationObserver: NSObject, WKNavigationDelegate {
    static let historyVisitDidOccurNotification = Notification.Name(
        "BrowserNavigationObserver.historyVisitDidOccur")
    static let historyVisitURLKey = "url"
    static let historyVisitTitleKey = "title"

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

        recordVisitIfAppropriate(tab: tab)

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
        recordVisitIfAppropriate(tab: tab)
    }

    private func recordVisitIfAppropriate(tab: Tab) {
        if tab.skipHistoryOnNextFinish {
            tab.skipHistoryOnNextFinish = false
            return
        }
        let url = tab.url
        guard Self.isRecordableURL(url) else { return }
        NotificationCenter.default.post(
            name: Self.historyVisitDidOccurNotification,
            object: nil,
            userInfo: [
                Self.historyVisitURLKey: url.absoluteString,
                Self.historyVisitTitleKey: tab.title as Any,
            ]
        )
    }

    private static func isRecordableURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard ["http", "https", "file"].contains(scheme) else { return false }
        let absolute = url.absoluteString
        if absolute == "about:blank" { return false }
        if absolute.hasPrefix("about:") { return false }
        return true
    }
}
