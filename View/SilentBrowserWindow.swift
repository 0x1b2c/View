import AppKit

final class SilentBrowserWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {
        // Swallow unhandled events silently instead of the default NSBeep.
    }
}
