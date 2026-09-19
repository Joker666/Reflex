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
    @Published private(set) var discoveredProfiles: [DiscoveredBrowserProfile] = []
    @Published private(set) var profileDiscoveryMessage: String?
    @Published var launchError: String?
    @Published var setupMessage: String?
    weak var chooserPresenter: (any ChooserPresenting)?

    private var queue = PendingURLQueue()
    private let launcher = BrowserLauncher()
    private let keychain: any APIKeyStoring
    private let jevClient = JevClient()
    private let defaults = UserDefaults.standard
    private let targetsKey = "browserTargets"
    private var iconCache: [String: NSImage] = [:]

    init(keychain: any APIKeyStoring = KeychainStore()) {
        self.keychain = keychain
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

    func receive(_ urls: [URL], sourceApplicationBundleIdentifier: String? = nil) {
        let needsRouting = queue.current == nil
        for url in urls where ["http", "https"].contains(url.scheme?.lowercased()) {
            queue.enqueue(url, sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier)
        }
        pendingURL = queue.current?.url
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
                advancePending()
            } catch {
                launchError = (error as? LocalizedError)?.errorDescription ?? "Reflex could not open the link."
                chooserPresenter?.presentChooser()
            }
        }
    }

    func cancelPending() {
        launchError = nil
        advancePending()
    }

    func icon(for target: BrowserTarget) -> NSImage? {
        if let cached = iconCache[target.bundleIdentifier] { return cached }
        guard let icon = launcher.icon(for: target) else { return nil }
        iconCache[target.bundleIdentifier] = icon
        return icon
    }

    private func advancePending() {
        pendingURL = queue.advance()?.url
        suggestedTargetID = nil
        isJevUnavailable = false
        if pendingURL == nil {
            chooserPresenter?.dismissChooser()
        } else {
            routePending()
        }
    }

    func rescanBrowsers() {
        targets = targets
            .filter(BrowserDiscovery.isSupportedTarget)
            .mergingDiscoveries(BrowserDiscovery().discover())
        discoverProfiles()
    }

    func discoverProfiles() {
        let result = BrowserProfileDiscovery().discover(for: targets)
        discoveredProfiles = result.profiles
        if result.unreadableBrowserNames.isEmpty {
            profileDiscoveryMessage = nil
        } else {
            profileDiscoveryMessage = "macOS did not allow profile access for \(result.unreadableBrowserNames.joined(separator: ", ")). You can enter a profile directory manually."
        }
    }

    func addDiscoveredProfile(_ profile: DiscoveredBrowserProfile) {
        guard !targets.contains(where: {
            $0.bundleIdentifier == profile.bundleIdentifier
                && $0.chromiumProfileDirectory == profile.profileDirectory
        }) else { return }

        targets.append(
            BrowserTarget(
                id: UUID(),
                name: "\(profile.browserName) — \(profile.profileName)",
                bundleIdentifier: profile.bundleIdentifier,
                purpose: "Browsing with \(profile.browserName) profile \(profile.profileName)",
                chromiumProfileDirectory: profile.profileDirectory,
                isEnabled: true
            )
        )
        discoverProfiles()
    }

    func addTarget(applicationURL: URL) {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              !targets.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        guard BrowserDiscovery.isSupportedBrowser(name: name, bundleIdentifier: bundleIdentifier) else {
            setupMessage = "Select Safari, Chrome, Dia, Comet, Helium, Edge, Phi, Zen, or Firefox."
            return
        }
        targets.append(
            BrowserTarget(
                id: UUID(),
                name: name,
                bundleIdentifier: bundleIdentifier,
                purpose: "General browsing in \(name)",
                chromiumProfileDirectory: nil,
                isEnabled: true
            )
        )
    }

    func removeTarget(id: UUID) {
        targets.removeAll { $0.id == id }
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
            chooserPresenter?.presentChooser()
            return
        case let .open(targetID):
            if let target = targets.first(where: { $0.id == targetID }) {
                openPending(in: target)
            }
            return
        case .choose:
            break
        }

        chooserPresenter?.presentChooser()

        guard let apiKey = try? keychain.readAPIKey(),
              let context = URLSanitizer.sanitize(
                url,
                sourceApplicationBundleIdentifier: queue.current?.sourceApplicationBundleIdentifier
              ) else {
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
