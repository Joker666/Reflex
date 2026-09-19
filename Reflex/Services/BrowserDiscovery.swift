import AppKit
import Foundation

protocol BrowserApplicationQuerying {
    func applicationURLs(toOpen url: URL) -> [URL]
}

struct WorkspaceBrowserApplicationQuery: BrowserApplicationQuerying {
    func applicationURLs(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }
}

struct BrowserDiscovery {
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
        let representativeURLs = [URL(string: "http://example.com")!, URL(string: "https://example.com")!]
        let candidates = representativeURLs.flatMap(query.applicationURLs(toOpen:))
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

            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? standardizedURL.deletingPathExtension().lastPathComponent
            result.append(
                DiscoveredBrowser(name: name, bundleIdentifier: identifier, applicationURL: standardizedURL)
            )
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
