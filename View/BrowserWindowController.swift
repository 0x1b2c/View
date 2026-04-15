import AppKit
import WebKit

final class BrowserWindowController: NSWindowController {
    private let webView: WKWebView

    init(webViewConfiguration: WKWebViewConfiguration, initialURL: URL, zoom: Double) {
        self.webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        self.webView.pageZoom = CGFloat(zoom)
        self.webView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "View"
        window.center()

        super.init(window: window)

        guard let contentView = window.contentView else { return }
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        webView.load(URLRequest(url: initialURL))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
