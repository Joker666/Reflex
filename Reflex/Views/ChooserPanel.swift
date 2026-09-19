import AppKit
import Combine
import SwiftUI

@MainActor
protocol ChooserPresenting: AnyObject {
    func presentChooser()
    func dismissChooser()
}

private final class ChooserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the chooser as a borderless panel at the pointer, near the clicked link.
@MainActor
final class ChooserPanelController: ChooserPresenting {
    private let state: AppState
    private var panel: ChooserPanel?
    private var hostingView: NSHostingView<ChooserView>?
    private var outsideClickMonitor: Any?
    private var contentChangeSubscription: AnyCancellable?

    init(state: AppState) {
        self.state = state
    }

    func presentChooser() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else {
            resizeToContent(keepingTopLeft: true)
            return
        }
        resizeToContent(keepingTopLeft: false)
        position(panel, near: NSEvent.mouseLocation)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        NSApplication.shared.activate(ignoringOtherApps: true)
        startOutsideClickMonitor()
    }

    func dismissChooser() {
        stopOutsideClickMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> ChooserPanel {
        let hostingView = NSHostingView(rootView: ChooserView(state: state))
        let panel = ChooserPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        self.hostingView = hostingView
        observeContentChanges()
        return panel
    }

    /// The panel is borderless, so it never resizes itself. Measure the SwiftUI content instead.
    private func resizeToContent(keepingTopLeft: Bool) {
        guard let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0, size != panel.frame.size else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        if keepingTopLeft {
            panel.setFrameTopLeftPoint(topLeft)
        }
    }

    private func observeContentChanges() {
        contentChangeSubscription = state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel?.isVisible == true else { return }
                self.resizeToContent(keepingTopLeft: true)
            }
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - 44, y: point.y - size.height + 12)
        if let visibleFrame = screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
            origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state.cancelPending()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}
