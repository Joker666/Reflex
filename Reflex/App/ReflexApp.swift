import SwiftUI

@main
struct ReflexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Reflex", systemImage: "arrow.triangle.branch") {
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Reflex") { NSApplication.shared.terminate(nil) }
        }

        Settings {
            SettingsView(state: appDelegate.state)
                .frame(width: 620, height: 520)
                .onAppear {
                    appDelegate.state.rescanBrowsers()
                    appDelegate.state.refreshDefaultBrowserStatus()
                }
        }
    }
}
