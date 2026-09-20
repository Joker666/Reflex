import AppKit
import Combine
import Foundation
import OSLog


private struct TargetProfileKey: Hashable {
    let bundleIdentifier: String
    let profileDirectory: String?
}

@MainActor
final class AppState: ObservableObject {
    @Published var targets: [BrowserTarget] = [] {
        didSet {
            updateAvailableTargets()
            persistTargets()
        }
    }
    @Published private(set) var availableTargets: [BrowserTarget] = []
    @Published private(set) var defaultBrowserStatus = DefaultBrowserStatus(ownsHTTP: false, ownsHTTPS: false)
    @Published private(set) var hasAPIKey = false
    @Published private(set) var profileAccessDeniedBrowsers: [String] = []
    @Published private(set) var missingProfileDataBrowsers: [String] = []
    @Published var setupMessage: String?
    @Published var chooserModifier = ChooserModifier.option {
        didSet { defaults.set(chooserModifier.rawValue, forKey: chooserModifierKey) }
    }
    @Published var usesJev = true {
        didSet {
            defaults.set(usesJev, forKey: usesJevKey)
            if !usesJev {
                linkRouter.cancelRouting()
            } else {
                linkRouter.retryPending()
            }
        }
    }
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
    var chooserPresenter: (any ChooserPresenting)? {
        get { linkRouter.chooserPresenter }
        set { linkRouter.chooserPresenter = newValue }
    }
    var settingsAction: (() -> Void)?

    private let launcher: any BrowserLaunching
    private let keychain: any APIKeyStoring
    private let jevClient: any JevDeciding
    private let defaults: UserDefaults
    private let browserScanner: any BrowserScanning
    private let defaultBrowserService: any DefaultBrowserServicing
    private let targetsKey = "browserTargets"
    private let menuBarItemKey = "showsMenuBarItem"
    private let chooserModifierKey = "chooserModifier"
    private let usesJevKey = "usesJev"
    private var iconCache: [String: NSImage] = [:]
    private var availabilityCache: [TargetProfileKey: Bool] = [:]
    private var storedShowsMenuBarItem = true
    private var knownProfileKeys: Set<TargetProfileKey> = []
    private var browsersWithReadProfiles: Set<String> = []
    private var browserScanTask: Task<Void, Never>?
    private var browserScanGeneration = 0
    private var routingChangeSubscription: AnyCancellable?
    private lazy var linkRouter = LinkRouter(
        launcher: launcher,
        keychain: keychain,
        jevClient: jevClient,
        availableTargets: { [weak self] in self?.availableTargets ?? [] },
        sourceApplicationName: { [weak self] in self?.applicationName(for: $0) },
        usesJev: { [weak self] in self?.usesJev ?? true }
    )

    var pendingURL: URL? { linkRouter.pendingURL }
    var suggestedTargetID: UUID? { linkRouter.suggestedTargetID }
    var isRouting: Bool { linkRouter.isRouting }
    var isJevUnavailable: Bool { linkRouter.isJevUnavailable }
    var skipsAutomaticSelection: Bool { linkRouter.skipsAutomaticSelection }
    var launchError: String? { linkRouter.launchError }

    init(
        keychain: any APIKeyStoring = KeychainStore(),
        launcher: any BrowserLaunching = BrowserLauncher(),
        jevClient: any JevDeciding = JevClient(),
        defaults: UserDefaults = .standard,
        browserScanner: any BrowserScanning = BrowserScanner(),
        defaultBrowserService: any DefaultBrowserServicing = DefaultBrowserService()
    ) {
        self.keychain = keychain
        self.launcher = launcher
        self.jevClient = jevClient
        self.defaults = defaults
        self.browserScanner = browserScanner
        self.defaultBrowserService = defaultBrowserService
        if let data = defaults.data(forKey: targetsKey),
           let storedTargets = try? JSONDecoder().decode([BrowserTarget].self, from: data) {
            targets = storedTargets.groupingTargetsByBrowser()
        }
        storedShowsMenuBarItem = defaults.object(forKey: menuBarItemKey) as? Bool ?? true
        chooserModifier = ChooserModifier.fromStoredValue(defaults.string(forKey: chooserModifierKey))
        usesJev = defaults.object(forKey: usesJevKey) as? Bool ?? true
        refreshDefaultBrowserStatus()
        hasAPIKey = (try? keychain.readAPIKey()) != nil
        updateAvailableTargets()
        routingChangeSubscription = linkRouter.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Launch Services lookups are slow, and SwiftUI asks for these on every pass.
    func isAvailable(_ target: BrowserTarget) -> Bool {
        let key = TargetProfileKey(
            bundleIdentifier: target.bundleIdentifier,
            profileDirectory: target.chromiumProfileDirectory
        )
        if let cached = availabilityCache[key] { return cached }
        var available = launcher.isAvailable(target)
        if available,
           let directory = target.chromiumProfileDirectory,
           browsersWithReadProfiles.contains(target.bundleIdentifier) {
            let profileKey = TargetProfileKey(
                bundleIdentifier: target.bundleIdentifier,
                profileDirectory: directory
            )
            available = knownProfileKeys.contains(profileKey)
        }
        availabilityCache[key] = available
        return available
    }

    private func updateAvailableTargets() {
        availableTargets = targets.filter { $0.isEnabled && isAvailable($0) }
    }

    func receive(
        _ urls: [URL],
        sourceApplicationBundleIdentifier: String? = nil,
        asksForChooser: Bool = false
    ) {
        linkRouter.receive(
            urls,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            asksForChooser: asksForChooser
        )
    }

    func openPending(in target: BrowserTarget) {
        linkRouter.openPending(in: target)
    }

    func cancelPending() {
        linkRouter.cancelPending()
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
        return bundle.displayName(fallbackURL: url)
    }

    func rescanBrowsers() {
        browserScanGeneration += 1
        let generation = browserScanGeneration
        browserScanTask?.cancel()
        let scanner = browserScanner
        let existingTargets = targets
        browserScanTask = Task { [weak self] in
            let scan = await scanner.scan(existingTargets: existingTargets)
            guard !Task.isCancelled,
                  let self,
                  generation == self.browserScanGeneration else { return }
            self.applyBrowserScan(scan)
            self.browserScanTask = nil
        }
    }

    private func applyBrowserScan(_ scan: BrowserScanResult) {
        iconCache.removeAll()
        availabilityCache.removeAll()
        let merged = targets
            .filter(BrowserDiscovery.isSupportedTarget)
            .mergingDiscoveries(scan.discoveries)

        let result = scan.profiles
        knownProfileKeys = Set(result.profiles.map {
            TargetProfileKey(bundleIdentifier: $0.bundleIdentifier, profileDirectory: $0.profileDirectory)
        })
        browsersWithReadProfiles = result.readableBundleIdentifiers
        profileAccessDeniedBrowsers = result.accessDeniedBrowserNames
        missingProfileDataBrowsers = result.missingProfileDataBrowserNames

        targets = merged
            .expandingProfiles(Dictionary(grouping: result.profiles, by: \.bundleIdentifier))
            .clearingGeneratedPurposes()

        ReflexLog.discovery.info("Rescanned browsers. Discovered \(self.targets.count, privacy: .public) targets (\(result.profiles.count, privacy: .public) profiles)")
        if !result.accessDeniedBrowserNames.isEmpty {
            ReflexLog.discovery.warning("Profile access denied for: \(result.accessDeniedBrowserNames.joined(separator: ", "), privacy: .private)")
        }
        linkRouter.retryPending()
    }

    func addTarget(applicationURL: URL) {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              !targets.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }
        let name = bundle.displayName(fallbackURL: applicationURL)
        guard BrowserDiscovery.isSupportedBrowser(name: name, bundleIdentifier: bundleIdentifier) else {
            setupMessage = SupportedBrowser.selectionInstruction
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
        defaultBrowserStatus = defaultBrowserService.currentStatus()
    }

    func makeDefaultBrowser() {
        setupMessage = nil
        Task {
            do {
                try await defaultBrowserService.makeDefault()
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
        linkRouter.retryPending()
    }

    func removeAPIKey() throws {
        try keychain.removeAPIKey()
        hasAPIKey = false
    }

    private func persistTargets() {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        defaults.set(data, forKey: targetsKey)
    }
}
