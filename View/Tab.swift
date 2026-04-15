import AppKit
import Foundation
import WebKit

final class Tab {
    var persistenceID: Int64?
    var url: URL
    var title: String?
    var webView: WKWebView?
    var position: Int
    var favicon: NSImage?

    var navigationObserver: NSObject?

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
