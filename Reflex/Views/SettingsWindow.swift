import AppKit
import SwiftUI

/// Reflex owns the settings window so it can open it at launch and quit when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        state.rescanBrowsers()
        state.refreshDefaultBrowserStatus()

        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentFrame = NSRect(x: 0, y: 0, width: 620, height: 520)
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

    /// macOS starts Reflex again for the next link, so it does not stay in the Dock.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            guard self.state.pendingURL == nil else { return }
            NSApplication.shared.terminate(nil)
        }
    }
}
