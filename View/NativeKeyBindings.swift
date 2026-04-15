import AppKit
import WebKit

enum NativeKeyBindings {
    static let tabKeyCode: UInt16 = 48

    static func install() -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if mods == .control || mods == [.control, .shift] {
                if event.keyCode == tabKeyCode {
                    let selector: Selector =
                        mods.contains(.shift)
                        ? Selector(("viewShowPreviousTab:"))
                        : Selector(("viewShowNextTab:"))
                    NSApp.sendAction(selector, to: nil, from: nil)
                    return nil
                }
            }

            guard mods == .control else { return event }
            guard let chars = event.charactersIgnoringModifiers else { return event }
            guard NSApp.keyWindow?.firstResponder is WKWebView else { return event }
            switch chars {
            case "f":
                NSApp.sendAction(
                    #selector(NSResponder.scrollPageDown(_:)), to: nil, from: nil)
                return nil
            case "b":
                NSApp.sendAction(
                    #selector(NSResponder.scrollPageUp(_:)), to: nil, from: nil)
                return nil
            default:
                return event
            }
        }!
    }
}
