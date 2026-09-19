import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var targets: [BrowserTarget] = [] {
        didSet { persistTargets() }
    }
    @Published private(set) var pendingURL: URL?
    @Published private(set) var defaultBrowserStatus = DefaultBrowserStatus(ownsHTTP: false, ownsHTTPS: false)
    @Published private(set) var suggestedTargetID: UUID?
    @Published private(set) var hasAPIKey = false
    @Published private(set) var isRouting = false
    @Published private(set) var isJevUnavailable = false
    @Published var launchError: String?
    @Published var setupMessage: String?

    private var queue = PendingURLQueue()
    private let launcher = BrowserLauncher()
    private let keychain = KeychainStore()
    private let jevClient = JevClient()
    private let defaults = UserDefaults.standard
    private let targetsKey = "browserTargets"

    init() {
        if let data = defaults.data(forKey: targetsKey),
           let storedTargets = try? JSONDecoder().decode([BrowserTarget].self, from: data) {
            targets = storedTargets
        }
        rescanBrowsers()
        refreshDefaultBrowserStatus()
        hasAPIKey = (try? keychain.readAPIKey()) != nil
    }

    var availableTargets: [BrowserTarget] {
        targets.filter { $0.isEnabled && launcher.isAvailable($0) }
    }

    func receive(_ urls: [URL]) {
        let needsRouting = queue.current == nil
        for url in urls where ["http", "https"].contains(url.scheme?.lowercased()) {
            queue.enqueue(url)
        }
        pendingURL = queue.current
        if pendingURL != nil {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows
                .first(where: { $0.title == "Reflex" })?
                .makeKeyAndOrderFront(nil)
        }
        if needsRouting, pendingURL != nil {
            routePending()
        }
    }

    func openPending(in target: BrowserTarget) {
        guard let url = pendingURL else { return }
        launchError = nil
        Task {
            do {
                try await launcher.open(url, in: target)
                pendingURL = queue.advance()
                suggestedTargetID = nil
                isJevUnavailable = false
                routePending()
            } catch {
                launchError = (error as? LocalizedError)?.errorDescription ?? "Reflex could not open the link."
            }
        }
    }

    func cancelPending() {
        pendingURL = queue.advance()
        launchError = nil
        suggestedTargetID = nil
        isJevUnavailable = false
        routePending()
    }

    func rescanBrowsers() {
        targets = targets.mergingDiscoveries(BrowserDiscovery().discover())
    }

    func refreshDefaultBrowserStatus() {
        defaultBrowserStatus = DefaultBrowserService().currentStatus()
    }

    func makeDefaultBrowser() {
        setupMessage = nil
        Task {
            do {
                try await DefaultBrowserService().makeDefault()
                refreshDefaultBrowserStatus()
            } catch {
                setupMessage = "macOS did not change the default browser. Open System Settings, select Desktop & Dock, and set Default web browser to Reflex."
                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        try keychain.saveAPIKey(trimmedKey)
        hasAPIKey = true
        if pendingURL != nil { routePending() }
    }

    func removeAPIKey() throws {
        try keychain.removeAPIKey()
        hasAPIKey = false
    }

    private func routePending() {
        guard let url = pendingURL, !isRouting else { return }
        let targets = availableTargets
        let localAction = RoutingPolicy.action(availableTargets: targets, decision: nil)
        switch localAction {
        case .setup:
            return
        case let .open(targetID):
            if let target = targets.first(where: { $0.id == targetID }) {
                openPending(in: target)
            }
            return
        case .choose:
            break
        }

        guard let apiKey = try? keychain.readAPIKey(),
              let context = URLSanitizer.sanitize(url) else {
            suggestedTargetID = nil
            isJevUnavailable = true
            return
        }

        isRouting = true
        isJevUnavailable = false
        Task {
            defer { isRouting = false }
            do {
                let decision = try await jevClient.decide(
                    context: context,
                    targets: targets,
                    apiKey: apiKey
                )
                apply(RoutingPolicy.action(availableTargets: targets, decision: decision), targets: targets)
            } catch {
                isJevUnavailable = true
                suggestedTargetID = nil
            }
        }
    }

    private func apply(_ action: RoutingAction, targets: [BrowserTarget]) {
        switch action {
        case .setup:
            suggestedTargetID = nil
        case let .open(targetID):
            if let target = targets.first(where: { $0.id == targetID }) {
                openPending(in: target)
            }
        case let .choose(targetID):
            suggestedTargetID = targetID
        }
    }

    private func persistTargets() {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: targetsKey)
    }
}
