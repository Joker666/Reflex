import AppKit
import SwiftUI

/// Reflex owns the settings window so it can manage its Dock and menu bar presence.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show(rescanBrowsers: Bool = true) {
        if rescanBrowsers {
            state.rescanBrowsers()
        }
        state.refreshDefaultBrowserStatus()

        let window = window ?? makeWindow()
        self.window = window
        // Reflex has no Dock icon while it routes links. Settings is a normal window.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentFrame = NSRect(x: 0, y: 0, width: 580, height: 480)
        let hostingView = NSHostingView(rootView: SettingsView(state: state))
        hostingView.frame = contentFrame
        let window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Reflex Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    nonisolated static func shouldTerminateOnClose(
        showsMenuBarItem: Bool,
        hasPendingURL: Bool
    ) -> Bool {
        !showsMenuBarItem && !hasPendingURL
    }

    /// Closing Settings always removes the Dock icon. The menu bar item can keep Reflex running.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.state.settingsDidClose()
            let shouldTerminate = Self.shouldTerminateOnClose(
                showsMenuBarItem: self.state.showsMenuBarItem,
                hasPendingURL: self.state.pendingURL != nil
            )
            guard shouldTerminate else {
                NSApplication.shared.setActivationPolicy(.accessory)
                return
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
