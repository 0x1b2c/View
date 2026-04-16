import AppKit
import WebKit

final class BrowserUIDelegate: NSObject, WKUIDelegate {
    weak var owner: BrowserWindowController?

    init(owner: BrowserWindowController) {
        self.owner = owner
        super.init()
    }

    // MARK: - New window / Cmd-click / target=_blank

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let owner, let url = navigationAction.request.url else { return nil }
        return owner.openBackgroundTab(with: url, configuration: configuration)
    }

    // MARK: - File picker

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            if response == .OK {
                completionHandler(panel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }

    // MARK: - JS dialogs (silent stubs, see TODO)

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        completionHandler(nil)
    }
}
