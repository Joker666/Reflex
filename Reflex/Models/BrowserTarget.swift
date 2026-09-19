import Foundation

struct BrowserTarget: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bundleIdentifier: String
    var purpose: String
    var chromiumProfileDirectory: String?
    var isEnabled: Bool
}

extension BrowserTarget {
    /// "Google Chrome (Personal)" describes the profile, so the browser name is the part before it.
    static func baseName(of name: String) -> String {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return name }
        let base = name[name.startIndex..<open].trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? name : base
    }

    static func profileName(_ profileName: String, of browserName: String) -> String {
        "\(browserName) (\(profileName))"
    }

    /// The text inside the trailing parentheses, which is the profile part of a name.
    static func profilePart(of name: String) -> String? {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return nil }
        let part = name[name.index(after: open)..<name.index(before: name.endIndex)]
        return part.isEmpty ? nil : String(part)
    }
}

// MARK: - Discovery & Profile Expansion

extension Array where Element == BrowserTarget {
    /// A browser with more than one profile becomes one target per profile. A browser with a
    /// single profile stays one plain target, so the chooser shows only the browser name.
    func expandingProfiles(
        _ profilesByBundleIdentifier: [String: [DiscoveredBrowserProfile]]
    ) -> [BrowserTarget] {
        var result: [BrowserTarget] = []
        var emittedBundleIdentifiers: Set<String> = []

        for target in self {
            let bundleIdentifier = target.bundleIdentifier
            guard !emittedBundleIdentifiers.contains(bundleIdentifier) else { continue }
            emittedBundleIdentifiers.insert(bundleIdentifier)

            var group = filter { $0.bundleIdentifier == bundleIdentifier }
            guard let profiles = profilesByBundleIdentifier[bundleIdentifier], !profiles.isEmpty else {
                result.append(contentsOf: group)
                continue
            }

            if profiles.count == 1,
               let plainIndex = group.firstIndex(where: { $0.chromiumProfileDirectory == nil }),
               !group.compactMap(\.chromiumProfileDirectory).contains(profiles[0].profileDirectory) {
                // Keep the plain browser name and the user's settings, but launch its one profile explicitly.
                group[plainIndex].chromiumProfileDirectory = profiles[0].profileDirectory
                result.append(contentsOf: group)
                continue
            }

            let browserName = group.first(where: { $0.chromiumProfileDirectory == nil })?.name
                ?? BrowserTarget.baseName(of: group[0].name)

            // The plain target takes the first free profile and keeps its purpose.
            if let plainIndex = group.firstIndex(where: { $0.chromiumProfileDirectory == nil }) {
                let used = Set(group.compactMap(\.chromiumProfileDirectory))
                if let profile = profiles.first(where: { !used.contains($0.profileDirectory) }) {
                    group[plainIndex].chromiumProfileDirectory = profile.profileDirectory
                    group[plainIndex].name = BrowserTarget.profileName(
                        profile.profileName,
                        of: browserName
                    )
                }
            }

            // A name Reflex made from the directory is not a user's name, so a later
            // scan that finds the real profile name replaces it.
            for index in group.indices {
                guard let directory = group[index].chromiumProfileDirectory,
                      let profile = profiles.first(where: { $0.profileDirectory == directory }),
                      let part = BrowserTarget.profilePart(of: group[index].name),
                      part != profile.profileName,
                      part == directory || BrowserProfileDiscovery.isPlaceholder(part) else { continue }
                let fallbackName = BrowserTarget.profileName(part, of: browserName)
                guard group[index].name == fallbackName else { continue }
                let name = BrowserTarget.profileName(profile.profileName, of: browserName)
                group[index].name = name
            }

            let configured = Set(group.compactMap(\.chromiumProfileDirectory))
            for profile in profiles where !configured.contains(profile.profileDirectory) {
                let name = BrowserTarget.profileName(profile.profileName, of: browserName)
                group.append(
                    BrowserTarget(
                        id: UUID(),
                        name: name,
                        bundleIdentifier: bundleIdentifier,
                        purpose: "",
                        chromiumProfileDirectory: profile.profileDirectory,
                        isEnabled: true
                    )
                )
            }
            result.append(contentsOf: group)
        }
        return result
    }

    /// Reflex wrote "General browsing in ..." before. It says nothing, so Jev should not read it.
    func clearingGeneratedPurposes() -> [BrowserTarget] {
        map { target in
            guard target.purpose.hasPrefix("General browsing in ") else { return target }
            var cleared = target
            cleared.purpose = ""
            return cleared
        }
    }

    func mergingDiscoveries(_ discoveries: [DiscoveredBrowser]) -> [BrowserTarget] {
        let discoveredIdentifiers = Set(discoveries.map(\.bundleIdentifier))
        var result = filter { discoveredIdentifiers.contains($0.bundleIdentifier) }
        let configured = Set(result.map(\.bundleIdentifier))

        for browser in discoveries where !configured.contains(browser.bundleIdentifier) {
            result.append(
                BrowserTarget(
                    id: UUID(),
                    name: browser.name,
                    bundleIdentifier: browser.bundleIdentifier,
                    purpose: "",
                    chromiumProfileDirectory: nil,
                    isEnabled: true
                )
            )
        }
        return result
    }
}
