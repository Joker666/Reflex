import AppKit
import SwiftUI

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
        // Reflex has no Dock icon while it routes links. Settings is a normal window.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentFrame = NSRect(x: 0, y: 0, width: 580, height: 480)
        let hostingView = NSHostingView(rootView: SettingsView(state: state, navigation: navigation))
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

        let toolbar = NSToolbar(identifier: "ReflexSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = navigation.selectedTab.identifier
        window.toolbar = toolbar

        window.center()
        return window
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            SettingsTab.general.identifier,
            SettingsTab.targets.identifier,
            SettingsTab.routing.identifier,
            .flexibleSpace
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            SettingsTab.general.identifier,
            SettingsTab.targets.identifier,
            SettingsTab.routing.identifier
        ]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.identifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .flexibleSpace {
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
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
        }
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
