import Foundation

struct RoutingContext: Codable, Equatable {
    var scheme: String
    var host: String
    var path: String
    var queryParameterNames: [String]
    var sourceApplicationBundleIdentifier: String?
}

struct RouteDecision: Equatable {
    var targetID: UUID
    var confidence: Double
}

enum RoutingAction: Equatable {
    case setup
    case open(UUID)
    case choose(suggestedTargetID: UUID?)
}
