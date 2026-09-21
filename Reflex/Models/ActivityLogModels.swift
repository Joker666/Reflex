import Foundation

enum ActivityRetentionPeriod: Int, CaseIterable, Identifiable, Codable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) days"
    }

    var timeInterval: TimeInterval {
        Double(rawValue) * 86_400
    }
}

enum RoutingOutcome: String, Codable, CaseIterable, Equatable {
    case autoRouted = "Auto-routed"
    case manualChoice = "Chooser selection"
    case modifierBypass = "Shortcut bypass"
    case singleTargetBypass = "Single target"
    case fallback = "Jev fallback"
}

struct TargetScore: Identifiable, Codable, Equatable {
    let id: UUID
    let targetID: UUID
    let targetName: String
    let score: Double

    init(id: UUID = UUID(), targetID: UUID, targetName: String, score: Double) {
        self.id = id
        self.targetID = targetID
        self.targetName = targetName
        self.score = score
    }
}

struct ActivityLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let scheme: String
    let host: String
    let path: String
    let queryParameterNames: [String]
    let sourceApplicationBundleIdentifier: String?
    let sourceApplicationName: String?

    // Result target
    let targetID: UUID
    let targetName: String
    let targetBundleIdentifier: String
    let targetProfileDirectory: String?

    // Outcome & Decision context
    let outcome: RoutingOutcome
    let jevConfidence: Double?
    let autoRouteThreshold: Double?
    let suggestedTargetID: UUID?
    let targetScores: [TargetScore]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        scheme: String,
        host: String,
        path: String,
        queryParameterNames: [String] = [],
        sourceApplicationBundleIdentifier: String? = nil,
        sourceApplicationName: String? = nil,
        targetID: UUID,
        targetName: String,
        targetBundleIdentifier: String,
        targetProfileDirectory: String? = nil,
        outcome: RoutingOutcome,
        jevConfidence: Double? = nil,
        autoRouteThreshold: Double? = nil,
        suggestedTargetID: UUID? = nil,
        targetScores: [TargetScore] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.scheme = scheme
        self.host = host
        self.path = path
        self.queryParameterNames = queryParameterNames
        self.sourceApplicationBundleIdentifier = sourceApplicationBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.targetID = targetID
        self.targetName = targetName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetProfileDirectory = targetProfileDirectory
        self.outcome = outcome
        self.jevConfidence = jevConfidence
        self.autoRouteThreshold = autoRouteThreshold
        self.suggestedTargetID = suggestedTargetID
        self.targetScores = targetScores
    }
}
