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

enum SupportedBrowser: CaseIterable {
    case safari
    case chrome
    case dia
    case comet
    case helium
    case edge
    case phi
    case zen
    case firefox

    var bundleIdentifierPrefixes: [String] {
        switch self {
        case .safari: ["com.apple.Safari"]
        case .chrome: ["com.google.Chrome"]
        case .dia: ["company.thebrowser.dia"]
        case .comet: ["ai.perplexity.comet"]
        case .helium: ["net.imput.helium"]
        case .edge: ["com.microsoft.edgemac"]
        case .phi: ["com.phibrowser.Mac"]
        case .zen: ["app.zen-browser.zen", "io.github.zen-browser.zen"]
        case .firefox: ["org.mozilla.firefox"]
        }
    }

    var matchingNames: [String] {
        switch self {
        case .safari: ["safari"]
        case .chrome: ["chrome", "google chrome"]
        case .dia: ["dia"]
        case .comet: ["comet"]
        case .helium: ["helium"]
        case .edge: ["edge", "microsoft edge"]
        case .phi: ["phi"]
        case .zen: ["zen", "zen browser"]
        case .firefox: ["firefox"]
        }
    }

    static func chromiumProfileDataDirectory(for bundleIdentifier: String) -> String? {
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

    static func matching(bundleIdentifier: String) -> SupportedBrowser? {
        allCases.first { browser in
            browser.bundleIdentifierPrefixes.contains { bundleIdentifier.hasPrefix($0) }
        }
    }

    static func matching(name: String, bundleIdentifier: String) -> SupportedBrowser? {
        if let browser = matching(bundleIdentifier: bundleIdentifier) {
            return browser
        }
        let normalizedName = name
            .lowercased()
            .replacingOccurrences(of: " developer edition", with: "")
            .replacingOccurrences(of: " canary", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { browser in
            browser.matchingNames.contains(normalizedName)
        }
    }
}

struct BrowserDiscovery {
    private static let discoveryURLs = [
        URL(string: "http://example.com")!,
        URL(string: "https://example.com")!,
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
        SupportedBrowser.matching(name: name, bundleIdentifier: bundleIdentifier) != nil
    }

    static func isSupportedTarget(_ target: BrowserTarget) -> Bool {
        SupportedBrowser.matching(bundleIdentifier: target.bundleIdentifier) != nil
    }
}
