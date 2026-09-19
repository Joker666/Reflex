import Foundation
import OSLog

@MainActor
final class LinkRouter: ObservableObject {
    @Published private(set) var pendingURL: URL?
    @Published private(set) var suggestedTargetID: UUID?
    @Published private(set) var isRouting = false
    @Published private(set) var isJevUnavailable = false
    @Published private(set) var skipsAutomaticSelection = false
    @Published private(set) var launchError: String?

    weak var chooserPresenter: (any ChooserPresenting)?

    private var queue = PendingURLQueue()
    private let launcher: any BrowserLaunching
    private let keychain: any APIKeyStoring
    private let jevClient: any JevDeciding
    private let availableTargets: () -> [BrowserTarget]
    private let sourceApplicationName: (String?) -> String?
    private var routingTask: Task<Void, Never>?
    private var routingLinkID: UUID?
    private var launchTask: Task<Void, Never>?
    private var launchingLinkID: UUID?

    init(
        launcher: any BrowserLaunching,
        keychain: any APIKeyStoring,
        jevClient: any JevDeciding,
        availableTargets: @escaping () -> [BrowserTarget],
        sourceApplicationName: @escaping (String?) -> String?
    ) {
        self.launcher = launcher
        self.keychain = keychain
        self.jevClient = jevClient
        self.availableTargets = availableTargets
        self.sourceApplicationName = sourceApplicationName
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

    func retryPending() {
        if pendingURL != nil { routePending() }
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

    private func routePending() {
        guard let link = queue.current, !isRouting else { return }
        let linkID = link.id
        let targets = availableTargets()
        skipsAutomaticSelection = link.asksForChooser
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
                link.url,
                sourceApplicationBundleIdentifier: sourceBundleIdentifier,
                sourceApplicationName: sourceApplicationName(sourceBundleIdentifier)
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
}
