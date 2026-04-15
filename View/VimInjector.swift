import Foundation
import ViewCore
import WebKit

enum VimInjector {
    static func makeUserScript(settings: Settings) -> WKUserScript {
        let source = buildSource(settings: settings)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    static func buildSource(settings: Settings) -> String {
        let whitelistJSON: String
        if let data = try? JSONSerialization.data(
            withJSONObject: settings.vim.whitelist, options: []),
            let text = String(data: data, encoding: .utf8)
        {
            whitelistJSON = text
        } else {
            whitelistJSON = "[]"
        }
        let enabledToken = settings.vim.enabled ? "true" : "false"

        return
            VimScript.template
            .replacingOccurrences(of: "__VIM_WHITELIST_JSON__", with: whitelistJSON)
            .replacingOccurrences(of: "__VIM_ENABLED__", with: enabledToken)
    }
}
