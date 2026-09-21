import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    private let chooserController: ChooserPanelController
    private let settingsController: SettingsWindowController
    private let onboardingController: OnboardingWindowController
    private let isTesting: Bool
    private var didReceiveURL = false

    override init() {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isTesting = isTesting
        let state = isTesting ? AppState(keychain: DisabledKeychainStore()) : AppState()
        self.state = state
        chooserController = ChooserPanelController(state: state)
        settingsController = SettingsWindowController(state: state)
        onboardingController = OnboardingWindowController(state: state)
        super.init()
        state.chooserPresenter = chooserController
        state.settingsAction = { [weak self] rescan in
            self?.openSettings(rescanBrowsers: rescan)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        state.rescanBrowsers()
        guard !isTesting else { return }
        if !state.hasCompletedOnboarding {
            onboardingController.show()
        // macOS delivers a link before this call, so a later launch without one opens Settings.
        } else if !didReceiveURL {
            openSettings(rescanBrowsers: false)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didReceiveURL = true
        let sourceApplicationBundleIdentifier = AppleEventSender.bundleIdentifier(
            from: NSAppleEventManager.shared().currentAppleEvent
        )
        state.receive(
            urls,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            asksForChooser: state.chooserModifier.isPressed(in: NSEvent.modifierFlags)
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
        openSettings(rescanBrowsers: true)
    }

    func openSettings(rescanBrowsers: Bool) {
        guard state.hasCompletedOnboarding else {
            onboardingController.show()
            return
        }
        settingsController.show(rescanBrowsers: rescanBrowsers)
    }
}
