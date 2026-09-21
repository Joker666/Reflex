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
    private let usesJev: () -> Bool
    private let confidenceThreshold: () -> Double
    private weak var activityLogger: (any ActivityLogging)?
    private var routingTask: Task<Void, Never>?
    private var routingLinkID: UUID?
    private var launchTask: Task<Void, Never>?
    private var launchingLinkID: UUID?
    private var isPausedForSettings = false
    private var activeDecision: RouteDecision?
    private var isAutoRouting = false

    init(
        launcher: any BrowserLaunching,
        keychain: any APIKeyStoring,
        jevClient: any JevDeciding,
        availableTargets: @escaping () -> [BrowserTarget],
        sourceApplicationName: @escaping (String?) -> String?,
        usesJev: @escaping () -> Bool = { true },
        confidenceThreshold: @escaping () -> Double = { RoutingPolicy.defaultThreshold },
        activityLogger: (any ActivityLogging)? = nil
    ) {
        self.launcher = launcher
        self.keychain = keychain
        self.jevClient = jevClient
        self.availableTargets = availableTargets
        self.sourceApplicationName = sourceApplicationName
        self.usesJev = usesJev
        self.confidenceThreshold = confidenceThreshold
        self.activityLogger = activityLogger
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
                self.recordActivityLog(link: link, chosenTarget: target)
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

    func cancelPendingForSettings() {
        isPausedForSettings = true
        cancelPending()
    }

    func pausePendingForOnboarding() {
        isPausedForSettings = true
        cancelPendingTasks()
        suggestedTargetID = nil
        isJevUnavailable = false
        skipsAutomaticSelection = false
        chooserPresenter?.dismissChooser()
    }

    func resumePendingAfterSettings() {
        guard isPausedForSettings else { return }
        isPausedForSettings = false
        routePending()
    }

    func cancelRouting() {
        routingTask?.cancel()
        routingTask = nil
        routingLinkID = nil
        isRouting = false
        suggestedTargetID = nil
        activeDecision = nil
        isAutoRouting = false
        isJevUnavailable = false
        if pendingURL != nil {
            chooserPresenter?.presentChooser()
        }
    }

    func retryPending() {
        guard pendingURL != nil else { return }
        if !usesJev() {
            cancelRouting()
            return
        }
        routePending()
    }

    private func advancePending(expectedLinkID: UUID) {
        guard queue.current?.id == expectedLinkID else { return }
        cancelPendingTasks()
        pendingURL = queue.advance()?.url
        suggestedTargetID = nil
        isJevUnavailable = false
        skipsAutomaticSelection = false
        activeDecision = nil
        isAutoRouting = false
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
        isAutoRouting = false
    }

    private func routePending() {
        guard let link = queue.current, !isRouting, !isPausedForSettings else { return }
        let linkID = link.id
        let targets = availableTargets()
        activeDecision = nil
        isAutoRouting = false
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

        guard usesJev() else {
            ReflexLog.routing.info("Automatic selection disabled by user preference; showing chooser")
            suggestedTargetID = nil
            isJevUnavailable = false
            return
        }

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
                guard !Task.isCancelled, self.queue.current?.id == linkID, self.usesJev() else { return }
                self.activeDecision = decision
                let currentTargets = self.availableTargets()
                ReflexLog.jev.info("Jev decision returned with confidence: \(decision.confidence, privacy: .public)")
                self.apply(
                    RoutingPolicy.action(
                        availableTargets: currentTargets,
                        decision: decision,
                        threshold: self.confidenceThreshold()
                    ),
                    targets: currentTargets,
                    linkID: linkID
                )
            } catch {
                guard !Task.isCancelled, self.queue.current?.id == linkID, self.usesJev() else { return }
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
            isAutoRouting = false
        case let .open(targetID):
            guard usesJev() else {
                suggestedTargetID = nil
                isAutoRouting = false
                return
            }
            if let target = targets.first(where: { $0.id == targetID }) {
                isAutoRouting = true
                openPending(in: target)
            }
        case let .choose(targetID):
            isAutoRouting = false
            suggestedTargetID = targetID
        }
    }

    private func recordActivityLog(link: PendingLink, chosenTarget: BrowserTarget) {
        guard let activityLogger, activityLogger.isLoggingEnabled else { return }
        let sourceBundleIdentifier = link.sourceApplicationBundleIdentifier
        let sourceAppName = sourceApplicationName(sourceBundleIdentifier)
        let sanitized = URLSanitizer.sanitize(
            link.url,
            sourceApplicationBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceAppName
        )
        let scheme = sanitized?.scheme ?? (link.url.scheme ?? "https")
        let host = sanitized?.host ?? (link.url.host() ?? "")
        let path = sanitized?.path ?? link.url.path()
        let queryParameterNames = sanitized?.queryParameterNames ?? []

        let outcome: RoutingOutcome
        if link.asksForChooser {
            outcome = .modifierBypass
        } else if isAutoRouting {
            outcome = .autoRouted
        } else if activeDecision != nil {
            outcome = .manualChoice
        } else if availableTargets().count == 1 {
            outcome = .singleTargetBypass
        } else {
            outcome = .fallback
        }

        var targetScores: [TargetScore] = []
        if let decision = activeDecision {
            let targets = availableTargets()
            for t in targets {
                if let score = decision.probabilities[t.id] {
                    targetScores.append(TargetScore(targetID: t.id, targetName: t.name, score: score))
                }
            }
            targetScores.sort { $0.score > $1.score }
        }

        let entry = ActivityLogEntry(
            scheme: scheme,
            host: host,
            path: path,
            queryParameterNames: queryParameterNames,
            sourceApplicationBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceAppName,
            targetID: chosenTarget.id,
            targetName: chosenTarget.name,
            targetBundleIdentifier: chosenTarget.bundleIdentifier,
            targetProfileDirectory: chosenTarget.chromiumProfileDirectory,
            outcome: outcome,
            jevConfidence: activeDecision?.confidence,
            autoRouteThreshold: confidenceThreshold(),
            suggestedTargetID: suggestedTargetID,
            targetScores: targetScores
        )
        activityLogger.record(entry)
    }
}
