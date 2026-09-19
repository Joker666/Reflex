import SwiftUI

@main
struct ReflexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    init() {
        let state: AppState
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            state = AppState(keychain: DisabledKeychainStore())
        } else {
            state = AppState()
        }
        _state = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup("Reflex") {
            ChooserView(state: state)
                .frame(minWidth: 420, minHeight: 380)
                .onAppear { appDelegate.state = state }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Reflex", systemImage: "arrow.triangle.branch") {
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Reflex") { NSApplication.shared.terminate(nil) }
        }

        Settings {
            SettingsView(state: state)
                .frame(width: 620, height: 520)
                .onAppear {
                    appDelegate.state = state
                    state.rescanBrowsers()
                    state.refreshDefaultBrowserStatus()
                }
        }
    }
}
