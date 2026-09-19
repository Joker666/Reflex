import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState? {
        didSet {
            guard let state else { return }
            for delivery in pendingDeliveries {
                state.receive(
                    delivery.urls,
                    sourceApplicationBundleIdentifier: delivery.sourceApplicationBundleIdentifier
                )
            }
            pendingDeliveries.removeAll()
        }
    }
    private var pendingDeliveries: [(
        urls: [URL],
        sourceApplicationBundleIdentifier: String?
    )] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApplicationBundleIdentifier = NSAppleEventManager.shared()
            .currentAppleEvent?
            .attributeDescriptor(forKeyword: keyOriginalAddressAttr)?
            .stringValue
        if let state {
            state.receive(
                urls,
                sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier
            )
        } else {
            pendingDeliveries.append((urls, sourceApplicationBundleIdentifier))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state?.refreshDefaultBrowserStatus()
    }
}
