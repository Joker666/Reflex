import AppKit
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
    @Published private(set) var pendingURL: URL?
    @Published private(set) var defaultBrowserStatus = DefaultBrowserStatus(ownsHTTP: false, ownsHTTPS: false)
    @Published private(set) var suggestedTargetID: UUID?
    @Published private(set) var hasAPIKey = false
    @Published private(set) var isRouting = false
    @Published private(set) var isJevUnavailable = false
    @Published private(set) var skipsAutomaticSelection = false
    @Published private(set) var profileAccessDeniedBrowsers: [String] = []
    @Published private(set) var missingProfileDataBrowsers: [String] = []
    @Published var launchError: String?
    @Published var setupMessage: String?
    @Published var chooserModifier = ChooserModifier.option {
        didSet { defaults.set(chooserModifier.rawValue, forKey: chooserModifierKey) }
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
    weak var chooserPresenter: (any ChooserPresenting)?
    var settingsAction: (() -> Void)?

    private var queue = PendingURLQueue()
    private let launcher: any BrowserLaunching
    private let keychain: any APIKeyStoring
    private let jevClient: any JevDeciding
    private let defaults: UserDefaults
    private let browserScanner: any BrowserScanning
    private let defaultBrowserService: any DefaultBrowserServicing
    private let targetsKey = "browserTargets"
    private let menuBarItemKey = "showsMenuBarItem"
    private let chooserModifierKey = "chooserModifier"
    private var iconCache: [String: NSImage] = [:]
    private var availabilityCache: [TargetProfileKey: Bool] = [:]
    private var storedShowsMenuBarItem = true
    private var knownProfileKeys: Set<TargetProfileKey> = []
    private var browsersWithReadProfiles: Set<String> = []
    private var browserScanTask: Task<Void, Never>?
    private var browserScanGeneration = 0
    private var routingTask: Task<Void, Never>?
    private var routingLinkID: UUID?
    private var launchTask: Task<Void, Never>?
    private var launchingLinkID: UUID?

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
            targets = storedTargets
        }
        storedShowsMenuBarItem = defaults.object(forKey: menuBarItemKey) as? Bool ?? true
        chooserModifier = ChooserModifier.fromStoredValue(defaults.string(forKey: chooserModifierKey))
        refreshDefaultBrowserStatus()
        hasAPIKey = (try? keychain.readAPIKey()) != nil
        updateAvailableTargets()
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
        let needsRouting = queue.current == nil
        for url in urls where url.isHTTPOrHTTPS {
            ReflexLog.routing.info("Enqueued link with scheme: \(url.scheme ?? "", privacy: .public), host: \(url.host() ?? "", privacy: .private)")
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
        guard let link = queue.current, launchTask == nil else { return }
        let linkID = link.id
        launchError = nil
        ReflexLog.launch.info("Opening link in target: \(target.name, privacy: .private) (\(target.bundleIdentifier, privacy: .public))")
        launchingLinkID = linkID
        launchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.launchingLinkID == linkID {
                    self.launchTask = nil
                    self.launchingLinkID = nil
                }
            }
            do {
                try await self.launcher.open(link.url, in: target)
                guard !Task.isCancelled, self.queue.current?.id == linkID else { return }
                self.advancePending(expectedLinkID: linkID)
            } catch {
                guard !Task.isCancelled, self.queue.current?.id == linkID else { return }
                ReflexLog.launch.error("Failed to open target \(target.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
                self.launchError = (error as? LocalizedError)?.errorDescription ?? "Reflex could not open the link."
                self.chooserPresenter?.presentChooser()
            }
        }
    }

    func cancelPending() {
        guard let linkID = queue.current?.id else { return }
        launchError = nil
        advancePending(expectedLinkID: linkID)
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

    private func advancePending(expectedLinkID: UUID) {
        guard queue.current?.id == expectedLinkID else { return }
        cancelPendingTasks()
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

    private func cancelPendingTasks() {
        routingTask?.cancel()
        routingTask = nil
        routingLinkID = nil
        launchTask?.cancel()
        launchTask = nil
        launchingLinkID = nil
        isRouting = false
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
        if pendingURL != nil { routePending() }
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
        if pendingURL != nil { routePending() }
    }

    func removeAPIKey() throws {
        try keychain.removeAPIKey()
        hasAPIKey = false
    }

    private func routePending() {
        guard let link = queue.current, !isRouting else { return }
        let linkID = link.id
        let url = link.url
        let targets = availableTargets
        skipsAutomaticSelection = link.asksForChooser
        // The configured modifier was held, so the user wants the full list.
        if skipsAutomaticSelection, !targets.isEmpty {
            ReflexLog.routing.info("Chooser modifier held; skipping automatic selection")
            suggestedTargetID = nil
            isJevUnavailable = false
            chooserPresenter?.presentChooser()
            return
        }
        let localAction = RoutingPolicy.action(availableTargets: targets, decision: nil)
        switch localAction {
        case .setup:
            ReflexLog.routing.info("No targets available; showing setup")
            chooserPresenter?.presentChooser()
            return
        case let .open(targetID):
            ReflexLog.routing.info("Single enabled target bypasses Jev decision")
            if let target = targets.first(where: { $0.id == targetID }) {
                openPending(in: target)
            }
            return
        case .choose:
            break
        }

        chooserPresenter?.presentChooser()

        let sourceBundleIdentifier = link.sourceApplicationBundleIdentifier
        guard let apiKey = try? keychain.readAPIKey(),
              let context = URLSanitizer.sanitize(
                url,
                sourceApplicationBundleIdentifier: sourceBundleIdentifier,
                sourceApplicationName: applicationName(for: sourceBundleIdentifier)
              ) else {
            ReflexLog.routing.info("No API key configured or sanitization failed; showing chooser fallback")
            suggestedTargetID = nil
            isJevUnavailable = true
            return
        }

        isRouting = true
        isJevUnavailable = false
        routingLinkID = linkID
        ReflexLog.jev.info("Requesting Jev decision for host: \(context.host, privacy: .private) with \(targets.count, privacy: .public) targets")
        routingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.routingLinkID == linkID {
                    self.routingTask = nil
                    self.routingLinkID = nil
                    self.isRouting = false
                }
            }
            do {
                let decision = try await self.jevClient.decide(
                    context: context,
                    targets: targets,
                    apiKey: apiKey
                )
                guard !Task.isCancelled, self.queue.current?.id == linkID else { return }
                ReflexLog.jev.info("Jev decision returned with confidence: \(decision.confidence, privacy: .public)")
                self.apply(
                    RoutingPolicy.action(availableTargets: targets, decision: decision),
                    targets: targets,
                    linkID: linkID
                )
            } catch {
                guard !Task.isCancelled, self.queue.current?.id == linkID else { return }
                ReflexLog.jev.error("Jev decision failed or timed out: \(error.localizedDescription, privacy: .private)")
                self.isJevUnavailable = true
                self.suggestedTargetID = nil
            }
        }
    }

    private func apply(_ action: RoutingAction, targets: [BrowserTarget], linkID: UUID) {
        guard queue.current?.id == linkID else { return }
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
