import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    private let chooserController: ChooserPanelController

    override init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let state = isTesting ? AppState(keychain: DisabledKeychainStore()) : AppState()
        self.state = state
        chooserController = ChooserPanelController(state: state)
        super.init()
        state.chooserPresenter = chooserController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApplicationBundleIdentifier = NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: keyOriginalAddressAttr)?
            .stringValue
        state.receive(
            urls,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.refreshDefaultBrowserStatus()
    }
}
