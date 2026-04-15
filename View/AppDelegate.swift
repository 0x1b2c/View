import Cocoa
import ViewCore
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var sessionController: SessionController?

    func applicationWillFinishLaunching(_ aNotification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            let paths = AppPaths.default
            let profileManager = ProfileManager(paths: paths)
            let profile = try profileManager.bootstrap()

            let settings = try Settings.loadOrCreate(at: paths.settingsFile(profileId: profile.id))
            let sessionStore = try SessionStore(
                fileURL: paths.sessionDatabase(profileId: profile.id))

            let configuration = Self.makeConfiguration(profile: profile)
            let controller = SessionController(
                sessionStore: sessionStore,
                settings: settings,
                webViewConfiguration: configuration
            )
            try controller.start()
            self.sessionController = controller
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "View failed to launch"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        sessionController?.quit()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private static func makeConfiguration(profile: Profile) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        if let uuid = UUID(uuidString: profile.dataStoreUUID) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
        }
        return config
    }
}
