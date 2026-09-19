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
    @Published private(set) var skipsAutomaticSelection = false
    @Published private(set) var unreadableProfileBrowsers: [String] = []
    @Published var launchError: String?
    @Published var setupMessage: String?
    /// Not @Published: MenuBarExtra writes this binding on every update, and a publish
    /// for an unchanged value starts an endless view update.
    var showsMenuBarItem: Bool {
        get { storedShowsMenuBarItem }
        set {
            guard newValue != storedShowsMenuBarItem else { return }
            objectWillChange.send()
            storedShowsMenuBarItem = newValue
            defaults.set(newValue, forKey: menuBarItemKey)
        }
    }
    weak var chooserPresenter: (any ChooserPresenting)?
    var settingsAction: (() -> Void)?

    private var queue = PendingURLQueue()
    private let launcher = BrowserLauncher()
    private let keychain: any APIKeyStoring
    private let jevClient = JevClient()
    private let defaults = UserDefaults.standard
    private let targetsKey = "browserTargets"
    private let menuBarItemKey = "showsMenuBarItem"
    private var iconCache: [String: NSImage] = [:]
    private var availabilityCache: [String: Bool] = [:]
    private var storedShowsMenuBarItem = true
    private var knownProfileKeys: Set<String> = []
    private var browsersWithReadProfiles: Set<String> = []

    init(keychain: any APIKeyStoring = KeychainStore()) {
        self.keychain = keychain
        if let data = defaults.data(forKey: targetsKey),
           let storedTargets = try? JSONDecoder().decode([BrowserTarget].self, from: data) {
            targets = storedTargets
        }
        storedShowsMenuBarItem = defaults.object(forKey: menuBarItemKey) as? Bool ?? true
        rescanBrowsers()
        refreshDefaultBrowserStatus()
        hasAPIKey = (try? keychain.readAPIKey()) != nil
    }

    var availableTargets: [BrowserTarget] {
        targets.filter { $0.isEnabled && isAvailable($0) }
    }

    /// Launch Services lookups are slow, and SwiftUI asks for these on every pass.
    func isAvailable(_ target: BrowserTarget) -> Bool {
        let key = "\(target.bundleIdentifier)|\(target.chromiumProfileDirectory ?? "")"
        if let cached = availabilityCache[key] { return cached }
        var available = launcher.isAvailable(target)
        if available,
           let directory = target.chromiumProfileDirectory,
           browsersWithReadProfiles.contains(target.bundleIdentifier) {
            available = knownProfileKeys.contains("\(target.bundleIdentifier)|\(directory)")
        }
        availabilityCache[key] = available
        return available
    }

    func receive(
        _ urls: [URL],
        sourceApplicationBundleIdentifier: String? = nil,
        asksForChooser: Bool = false
    ) {
        let needsRouting = queue.current == nil
        for url in urls where ["http", "https"].contains(url.scheme?.lowercased()) {
            queue.enqueue(
                url,
                sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
                asksForChooser: asksForChooser
            )
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

    private func applicationName(for bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url) else {
            return nil
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func advancePending() {
        pendingURL = queue.advance()?.url
        suggestedTargetID = nil
        isJevUnavailable = false
        skipsAutomaticSelection = false
        if pendingURL == nil {
            chooserPresenter?.dismissChooser()
        } else {
            routePending()
        }
    }

    func rescanBrowsers() {
        iconCache.removeAll()
        availabilityCache.removeAll()
        let merged = targets
            .filter(BrowserDiscovery.isSupportedTarget)
            .mergingDiscoveries(BrowserDiscovery().discover())

        let result = BrowserProfileDiscovery().discover(for: merged)
        knownProfileKeys = Set(result.profiles.map(\.id))
        browsersWithReadProfiles = result.readableBundleIdentifiers
        unreadableProfileBrowsers = result.unreadableBrowserNames

        targets = merged
            .expandingProfiles(Dictionary(grouping: result.profiles, by: \.bundleIdentifier))
            .clearingGeneratedPurposes()
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
                purpose: "",
                chromiumProfileDirectory: nil,
                isEnabled: true
            )
        )
    }

    func openSettings() {
        cancelPending()
        chooserPresenter?.dismissChooser()
        settingsAction?()
    }

    func openFullDiskAccessSettings() {
        let addresses = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for address in addresses {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
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
        skipsAutomaticSelection = queue.current?.asksForChooser ?? false
        // Option held: the user wants the list, even with one target or a sure answer.
        if skipsAutomaticSelection, !targets.isEmpty {
            suggestedTargetID = nil
            isJevUnavailable = false
            chooserPresenter?.presentChooser()
            return
        }
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

        let sourceBundleIdentifier = queue.current?.sourceApplicationBundleIdentifier
        guard let apiKey = try? keychain.readAPIKey(),
              let context = URLSanitizer.sanitize(
                url,
                sourceApplicationBundleIdentifier: sourceBundleIdentifier,
                sourceApplicationName: applicationName(for: sourceBundleIdentifier)
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
