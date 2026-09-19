import AppKit
import Foundation

extension Bundle {
    var displayName: String? {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
    }

    func displayName(fallbackURL: URL) -> String {
        displayName ?? fallbackURL.deletingPathExtension().lastPathComponent
    }
}

protocol BrowserApplicationQuerying {
    func applicationURLs(toOpen url: URL) -> [URL]
}

struct WorkspaceBrowserApplicationQuery: BrowserApplicationQuerying {
    func applicationURLs(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }
}

struct BrowserDiscovery {
    private static let discoveryURLs = [
        URL(string: "http://example.com")!,
        URL(string: "https://example.com")!,
    ]

    private static let supportedBundleIdentifierPrefixes = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.dia",
        "ai.perplexity.comet",
        "net.imput.helium",
        "com.microsoft.edgemac",
        "com.phibrowser.Mac",
        "app.zen-browser.zen",
        "io.github.zen-browser.zen",
        "org.mozilla.firefox",
    ]

    private static let supportedApplicationNames = [
        "safari", "chrome", "google chrome", "dia", "comet", "helium",
        "edge", "microsoft edge", "phi", "zen", "zen browser", "firefox",
    ]

    var query: BrowserApplicationQuerying
    var selfBundleIdentifier: String?

    init(
        query: BrowserApplicationQuerying = WorkspaceBrowserApplicationQuery(),
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.query = query
        self.selfBundleIdentifier = selfBundleIdentifier
    }

    func discover() -> [DiscoveredBrowser] {
        let candidates = Self.discoveryURLs.flatMap(query.applicationURLs(toOpen:))
        var seenBundleIdentifiers = Set<String>()
        var seenApplicationURLs = Set<URL>()
        var result: [DiscoveredBrowser] = []

        for applicationURL in candidates {
            let standardizedURL = applicationURL.standardizedFileURL
            guard let bundle = Bundle(url: standardizedURL) else { continue }
            let identifier = bundle.bundleIdentifier ?? standardizedURL.path
            guard identifier != selfBundleIdentifier else { continue }
            let isNew = bundle.bundleIdentifier.map { seenBundleIdentifiers.insert($0).inserted }
                ?? seenApplicationURLs.insert(standardizedURL).inserted
            guard isNew else { continue }

            let name = bundle.displayName(fallbackURL: standardizedURL)
            guard Self.isSupportedBrowser(name: name, bundleIdentifier: identifier) else { continue }
            result.append(
                DiscoveredBrowser(name: name, bundleIdentifier: identifier, applicationURL: standardizedURL)
            )
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isSupportedBrowser(name: String, bundleIdentifier: String) -> Bool {
        if supportedBundleIdentifierPrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return true
        }

        let normalizedName = name
            .lowercased()
            .replacingOccurrences(of: " developer edition", with: "")
            .replacingOccurrences(of: " canary", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return supportedApplicationNames.contains(normalizedName)
    }

    static func isSupportedTarget(_ target: BrowserTarget) -> Bool {
        supportedBundleIdentifierPrefixes.contains { target.bundleIdentifier.hasPrefix($0) }
    }
}
