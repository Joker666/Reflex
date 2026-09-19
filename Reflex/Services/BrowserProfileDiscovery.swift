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
    var accessDeniedBrowserNames: [String]
    var missingProfileDataBrowserNames: [String]
    var readableBundleIdentifiers: Set<String> = []
}

struct BrowserProfileDiscovery {
    var applicationSupportURL: URL
    var fileManager: FileManager
    var dataLoader: (URL) throws -> Data

    init(
        applicationSupportURL: URL? = nil,
        fileManager: FileManager = .default,
        dataLoader: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.fileManager = fileManager
        self.dataLoader = dataLoader
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
        let accessDeniedBrowserNames = results.compactMap(\.accessDeniedBrowserName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let missingProfileDataBrowserNames = results.compactMap(\.missingProfileDataBrowserName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return BrowserProfileDiscoveryResult(
            profiles: profiles,
            accessDeniedBrowserNames: accessDeniedBrowserNames,
            missingProfileDataBrowserNames: missingProfileDataBrowserNames,
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
        accessDeniedBrowserName: String?,
        missingProfileDataBrowserName: String?,
        readableBundleIdentifier: String?
    ) {
        guard let relativeDirectory = Self.relativeDataDirectory(for: bundleIdentifier) else {
            return ([], nil, nil, nil)
        }
        let dataDirectory = applicationSupportURL.appending(path: relativeDirectory, directoryHint: .isDirectory)
        let localStateURL = dataDirectory.appending(path: "Local State")
        let data: Data
        do {
            data = try dataLoader(localStateURL)
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.Code.fileReadNoPermission.rawValue {
                return ([], browserName, nil, nil)
            }
            return ([], nil, browserName, nil)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return ([], nil, browserName, nil)
        }

        let profiles: [DiscoveredBrowserProfile] = infoCache.compactMap { directory, value in
            guard BrowserLauncher.isValidProfileDirectory(directory),
                  fileManager.fileExists(atPath: dataDirectory.appending(path: directory).path) else {
                return nil
            }
            let metadata = value as? [String: Any] ?? [:]
            let profileName = Self.profileName(from: metadata, directory: directory)
            return DiscoveredBrowserProfile(
                browserName: browserName,
                bundleIdentifier: bundleIdentifier,
                profileDirectory: directory,
                profileName: profileName
            )
        }
        return (profiles, nil, nil, bundleIdentifier)
    }

    /// Edge leaves `name` at "Profile 2" and keeps the person's name in the account fields.
    static func profileName(from metadata: [String: Any], directory: String) -> String {
        let accountName = [
            text(metadata["edge_account_first_name"]),
            text(metadata["edge_account_last_name"]),
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let candidates = [
            text(metadata["name"]).flatMap { isPlaceholder($0) ? nil : $0 },
            // The account name is shorter than the full account label, which can carry an id.
            accountName.isEmpty ? nil : accountName,
            text(metadata["gaia_name"]),
            text(metadata["user_name"]),
        ]
        return candidates.compactMap { $0 }.first ?? directory
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "Profile 2" and "Person 1" are the names a browser gives a profile without a name.
    static func isPlaceholder(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        guard parts.count == 2, Int(parts[1]) != nil else { return false }
        let first = parts[0].lowercased()
        return first == "profile" || first == "person"
    }

    private static func relativeDataDirectory(for bundleIdentifier: String) -> String? {
        SupportedBrowser.chromiumProfileDataDirectory(for: bundleIdentifier)
    }
}
