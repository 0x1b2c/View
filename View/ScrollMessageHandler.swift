import AppKit
import WebKit

final class ScrollMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "viewScroll"

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? String else { return }
        switch body {
        case "top":
            NSApp.sendAction(
                #selector(NSResponder.scrollToBeginningOfDocument(_:)), to: nil, from: nil)
        case "bottom":
            NSApp.sendAction(
                #selector(NSResponder.scrollToEndOfDocument(_:)), to: nil, from: nil)
        default:
            break
        }
    }
}
