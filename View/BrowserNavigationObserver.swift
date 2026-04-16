import AppKit
import WebKit

final class BrowserNavigationObserver: NSObject, WKNavigationDelegate {
    static let historyVisitDidOccurNotification = Notification.Name(
        "BrowserNavigationObserver.historyVisitDidOccur")
    static let historyTitleDidUpdateNotification = Notification.Name(
        "BrowserNavigationObserver.historyTitleDidUpdate")
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
        if let title = webView.title, !title.isEmpty,
            BrowserWindowController.isRecordableHistoryURL(tab.url)
        {
            NotificationCenter.default.post(
                name: Self.historyTitleDidUpdateNotification,
                object: nil,
                userInfo: [
                    Self.historyVisitURLKey: tab.url.absoluteString,
                    Self.historyVisitTitleKey: title,
                ]
            )
        }
        FaviconFetcher.shared.fetch(for: webView) { [weak tab, weak owner] image in
            guard let tab, let owner, let image else { return }
            tab.favicon = image
            owner.refreshAfterNavigation(tab: tab)
        }
    }
}
