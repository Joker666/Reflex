import Foundation

enum RoutingPolicy {
    static let defaultThreshold = 0.85

    static func clampedThreshold(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func action(
        availableTargets: [BrowserTarget],
        decision: RouteDecision?,
        threshold: Double = defaultThreshold
    ) -> RoutingAction {
        guard !availableTargets.isEmpty else { return .setup }
        if availableTargets.count == 1 {
            return .open(availableTargets[0].id)
        }
        guard let decision else { return .choose(suggestedTargetID: nil) }
        let validTargetIDs = Set(availableTargets.map(\.id))
        guard validTargetIDs.contains(decision.targetID) else {
            return .choose(suggestedTargetID: nil)
        }
        if decision.confidence >= clampedThreshold(threshold) {
            return .open(decision.targetID)
        }
        return .choose(suggestedTargetID: decision.targetID)
    }
}
