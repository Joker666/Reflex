import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState? {
        didSet {
            guard !pendingURLs.isEmpty else { return }
            state?.receive(pendingURLs)
            pendingURLs.removeAll()
        }
    }
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let state {
            state.receive(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state?.refreshDefaultBrowserStatus()
    }
}
