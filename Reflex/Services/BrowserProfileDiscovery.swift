import Foundation

struct DiscoveredBrowserProfile: Identifiable, Equatable {
    var id: String { "\(bundleIdentifier)|\(profileDirectory)" }

    var browserName: String
    var bundleIdentifier: String
    var profileDirectory: String
    var profileName: String
}

struct BrowserProfileDiscoveryResult: Equatable {
    var profiles: [DiscoveredBrowserProfile]
    var unreadableBrowserNames: [String]
    var readableBundleIdentifiers: Set<String> = []
}

struct BrowserProfileDiscovery {
    var applicationSupportURL: URL
    var fileManager: FileManager

    init(
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func discover(for targets: [BrowserTarget]) -> BrowserProfileDiscoveryResult {
        let browsers = Dictionary(
            targets.map { ($0.bundleIdentifier, baseBrowserName(for: $0.bundleIdentifier, in: targets)) },
            uniquingKeysWith: { first, _ in first }
        )

        let results = browsers.map { bundleIdentifier, browserName in
            discover(browserName: browserName, bundleIdentifier: bundleIdentifier)
        }
        let profiles = results.flatMap(\.profiles).sorted {
            let browserOrder = $0.browserName.localizedCaseInsensitiveCompare($1.browserName)
            if browserOrder == .orderedSame {
                // The default profile comes first, so it keeps the plain target's purpose.
                if ($0.profileDirectory == "Default") != ($1.profileDirectory == "Default") {
                    return $0.profileDirectory == "Default"
                }
                return $0.profileName.localizedStandardCompare($1.profileName) == .orderedAscending
            }
            return browserOrder == .orderedAscending
        }
        let unreadableBrowserNames = results.compactMap(\.unreadableBrowserName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return BrowserProfileDiscoveryResult(
            profiles: profiles,
            unreadableBrowserNames: unreadableBrowserNames,
            readableBundleIdentifiers: Set(results.compactMap(\.readableBundleIdentifier))
        )
    }

    /// A target that already carries a profile has the profile in its name, so it is not a base name.
    private func baseBrowserName(for bundleIdentifier: String, in targets: [BrowserTarget]) -> String {
        let group = targets.filter { $0.bundleIdentifier == bundleIdentifier }
        if let plain = group.first(where: { $0.chromiumProfileDirectory == nil }) {
            return plain.name
        }
        return group.first.map { BrowserTarget.baseName(of: $0.name) } ?? bundleIdentifier
    }

    private func discover(
        browserName: String,
        bundleIdentifier: String
    ) -> (
        profiles: [DiscoveredBrowserProfile],
        unreadableBrowserName: String?,
        readableBundleIdentifier: String?
    ) {
        guard let relativeDirectory = Self.relativeDataDirectory(for: bundleIdentifier) else {
            return ([], nil, nil)
        }
        let dataDirectory = applicationSupportURL.appending(path: relativeDirectory, directoryHint: .isDirectory)
        let localStateURL = dataDirectory.appending(path: "Local State")
        guard fileManager.fileExists(atPath: localStateURL.path) else { return ([], nil, nil) }
        guard let data = try? Data(contentsOf: localStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return ([], browserName, nil)
        }

        let profiles: [DiscoveredBrowserProfile] = infoCache.compactMap { directory, value in
            guard BrowserLauncher.isValidProfileDirectory(directory),
                  fileManager.fileExists(atPath: dataDirectory.appending(path: directory).path) else {
                return nil
            }
            let metadata = value as? [String: Any]
            let storedName = (metadata?["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let profileName = storedName.flatMap { $0.isEmpty ? nil : $0 } ?? directory
            return DiscoveredBrowserProfile(
                browserName: browserName,
                bundleIdentifier: bundleIdentifier,
                profileDirectory: directory,
                profileName: profileName
            )
        }
        return (profiles, nil, bundleIdentifier)
    }

    private static func relativeDataDirectory(for bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.google.Chrome": "Google/Chrome"
        case "com.microsoft.edgemac": "Microsoft Edge"
        case "ai.perplexity.comet": "Comet"
        case "company.thebrowser.dia": "Dia/User Data"
        case "net.imput.helium": "net.imput.helium"
        case "com.phibrowser.Mac": "com.phibrowser.Mac"
        default: nil
        }
    }
}
