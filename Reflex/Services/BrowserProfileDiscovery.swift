import Foundation

struct DiscoveredBrowserProfile: Identifiable, Equatable {
    var id: String { "\(bundleIdentifier)|\(profileDirectory)" }

    var browserName: String
    var bundleIdentifier: String
    var profileDirectory: String
}

struct BrowserProfileDiscoveryResult: Equatable {
    var profiles: [DiscoveredBrowserProfile]
    var unreadableBrowserNames: [String]
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
        let configuredProfiles = Set(targets.compactMap { target -> String? in
            guard let directory = target.chromiumProfileDirectory else { return nil }
            return key(bundleIdentifier: target.bundleIdentifier, profileDirectory: directory)
        })
        let browsers = Dictionary(
            targets.map { ($0.bundleIdentifier, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        let results = browsers.map { bundleIdentifier, browserName in
            discover(
                browserName: browserName,
                bundleIdentifier: bundleIdentifier,
                excluding: configuredProfiles
            )
        }
        let profiles = results.flatMap(\.profiles).sorted {
            let browserOrder = $0.browserName.localizedCaseInsensitiveCompare($1.browserName)
            if browserOrder == .orderedSame {
                return $0.profileDirectory.localizedStandardCompare($1.profileDirectory) == .orderedAscending
            }
            return browserOrder == .orderedAscending
        }
        let unreadableBrowserNames = results.compactMap(\.unreadableBrowserName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return BrowserProfileDiscoveryResult(
            profiles: profiles,
            unreadableBrowserNames: unreadableBrowserNames
        )
    }

    private func discover(
        browserName: String,
        bundleIdentifier: String,
        excluding configuredProfiles: Set<String>
    ) -> (profiles: [DiscoveredBrowserProfile], unreadableBrowserName: String?) {
        guard let relativeDirectory = Self.relativeDataDirectory(for: bundleIdentifier) else {
            return ([], nil)
        }
        let dataDirectory = applicationSupportURL.appending(path: relativeDirectory, directoryHint: .isDirectory)
        let localStateURL = dataDirectory.appending(path: "Local State")
        guard fileManager.fileExists(atPath: localStateURL.path) else { return ([], nil) }
        guard let data = try? Data(contentsOf: localStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return ([], browserName)
        }

        let profiles: [DiscoveredBrowserProfile] = infoCache.keys.compactMap { directory in
            guard BrowserLauncher.isValidProfileDirectory(directory),
                  !configuredProfiles.contains(key(
                    bundleIdentifier: bundleIdentifier,
                    profileDirectory: directory
                  )),
                  fileManager.fileExists(atPath: dataDirectory.appending(path: directory).path) else {
                return nil
            }
            return DiscoveredBrowserProfile(
                browserName: browserName,
                bundleIdentifier: bundleIdentifier,
                profileDirectory: directory
            )
        }
        return (profiles, nil)
    }

    private func key(bundleIdentifier: String, profileDirectory: String) -> String {
        "\(bundleIdentifier)|\(profileDirectory)"
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
