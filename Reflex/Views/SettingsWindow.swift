import AppKit
import SwiftUI

/// Settings and onboarding are normal windows. Reflex has a Dock icon only while one is open.
@MainActor
enum AppWindowPresence {
    static func show(_ window: NSWindow) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closing the window removes the Dock icon. The menu bar item or a pending link keeps Reflex running.
    static func windowDidClose(state: AppState) {
        let shouldTerminate = shouldTerminateOnClose(
            showsMenuBarItem: state.showsMenuBarItem,
            hasPendingURL: state.pendingURL != nil
        )
        if shouldTerminate {
            NSApplication.shared.terminate(nil)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    nonisolated static func shouldTerminateOnClose(
        showsMenuBarItem: Bool,
        hasPendingURL: Bool
    ) -> Bool {
        !showsMenuBarItem && !hasPendingURL
    }
}

/// Reflex owns the settings window so it can manage its Dock and menu bar presence.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let state: AppState
    private let navigation = SettingsNavigationState()
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
        AppWindowPresence.show(window)
    }

    private func makeWindow() -> NSWindow {
        let contentFrame = NSRect(x: 0, y: 0, width: 640, height: 520)
        let hostingView = NSHostingView(rootView: SettingsView(
            state: state,
            navigation: navigation,
            activityLog: state.activityLogStore
        ))
        hostingView.frame = contentFrame
        let window = NSWindow(
            contentRect: contentFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .preference
        window.contentView = hostingView
        window.title = navigation.selectedTab.rawValue
        window.isReleasedWhenClosed = false
        window.delegate = self

        let toolbar = NSToolbar(identifier: "ReflexSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = navigation.selectedTab.identifier
        window.toolbar = toolbar

        window.center()
        return window
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.identifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab.allCases.first(where: { $0.identifier == itemIdentifier }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.rawValue)
        item.target = self
        item.action = #selector(tabSelected(_:))
        return item
    }

    @objc private func tabSelected(_ sender: NSToolbarItem) {
        if let tab = SettingsTab.allCases.first(where: { $0.identifier == sender.itemIdentifier }) {
            navigation.selectedTab = tab
            window?.toolbar?.selectedItemIdentifier = tab.identifier
            window?.title = tab.rawValue
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.state.settingsDidClose()
            AppWindowPresence.windowDidClose(state: self.state)
        }
    }
}
