import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    private let chooserController: ChooserPanelController
    private let settingsController: SettingsWindowController
    private var didReceiveURL = false

    override init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let state = isTesting ? AppState(keychain: DisabledKeychainStore()) : AppState()
        self.state = state
        chooserController = ChooserPanelController(state: state)
        settingsController = SettingsWindowController(state: state)
        super.init()
        state.chooserPresenter = chooserController
        state.settingsAction = { [weak settingsController] in settingsController?.show() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        // macOS delivers a link before this call, so a launch without one opens Settings.
        if !didReceiveURL {
            openSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didReceiveURL = true
        let sourceApplicationBundleIdentifier = NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: keyOriginalAddressAttr)?
            .stringValue
        state.receive(
            urls,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            asksForChooser: NSEvent.modifierFlags.contains(.option)
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.refreshDefaultBrowserStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    func openSettings() {
        settingsController.show()
    }
}
