import Foundation

struct BrowserTarget: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var purpose: String
    var chromiumProfileDirectory: String?
    var isEnabled: Bool
}

struct DiscoveredBrowser: Equatable {
    var name: String
    var bundleIdentifier: String
    var applicationURL: URL
}

extension Array where Element == BrowserTarget {
    func mergingDiscoveries(_ discoveries: [DiscoveredBrowser]) -> [BrowserTarget] {
        var result = self
        let configured = Set(map(\.bundleIdentifier))

        for browser in discoveries where !configured.contains(browser.bundleIdentifier) {
            result.append(
                BrowserTarget(
                    id: UUID(),
                    name: browser.name,
                    bundleIdentifier: browser.bundleIdentifier,
                    purpose: "General browsing in \(browser.name)",
                    chromiumProfileDirectory: nil,
                    isEnabled: true
                )
            )
        }
        return result
    }
}
