import OSLog
import SwiftUI

@main
struct ReflexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        ReflexMenuBar(state: appDelegate.state, openSettings: appDelegate.openSettings)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

/// A scene of its own so the menu bar item can follow the stored preference.
private struct ReflexMenuBar: Scene {
    @ObservedObject var state: AppState
    let openSettings: () -> Void

    private var versionText: String? {
        AppVersion.formatted()
    }

    var body: some Scene {
        MenuBarExtra(
            "Reflex",
            systemImage: "arrow.triangle.branch",
            isInserted: $state.showsMenuBarItem
        ) {
            Button("Settings…") { openSettings() }
            if let versionText {
                Text(versionText)
                    .disabled(true)
            }
            Divider()
            Button("Quit Reflex") { NSApplication.shared.terminate(nil) }
        }
    }
}

enum AppVersion {
    static func formatted(
        shortVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        buildVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    ) -> String? {
        if let shortVersion, !shortVersion.isEmpty {
            return "Version \(shortVersion)"
        }
        if let buildVersion, !buildVersion.isEmpty {
            return "Version \(buildVersion)"
        }
        return nil
    }
}

enum ReflexLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.rafi.Reflex"

    static let routing = Logger(subsystem: subsystem, category: "Routing")
    static let jev = Logger(subsystem: subsystem, category: "Jev")
    static let launch = Logger(subsystem: subsystem, category: "Launch")
    static let discovery = Logger(subsystem: subsystem, category: "Discovery")
}
