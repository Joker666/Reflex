import AppKit
import Foundation

struct DefaultBrowserStatus: Equatable {
    var ownsHTTP: Bool
    var ownsHTTPS: Bool

    var isComplete: Bool { ownsHTTP && ownsHTTPS }
}

struct DefaultBrowserService {
    static func status(
        defaultHTTPBundleIdentifier: String?,
        defaultHTTPSBundleIdentifier: String?,
        reflexBundleIdentifier: String
    ) -> DefaultBrowserStatus {
        DefaultBrowserStatus(
            ownsHTTP: defaultHTTPBundleIdentifier == reflexBundleIdentifier,
            ownsHTTPS: defaultHTTPSBundleIdentifier == reflexBundleIdentifier
        )
    }

    private static let sampleHTTPURL = URL(string: "http://example.com")!
    private static let sampleHTTPSURL = URL(string: "https://example.com")!

    func currentStatus() -> DefaultBrowserStatus {
        let workspace = NSWorkspace.shared
        let httpIdentifier = workspace.urlForApplication(toOpen: Self.sampleHTTPURL)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        let httpsIdentifier = workspace.urlForApplication(toOpen: Self.sampleHTTPSURL)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return Self.status(
            defaultHTTPBundleIdentifier: httpIdentifier,
            defaultHTTPSBundleIdentifier: httpsIdentifier,
            reflexBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.rafi.Reflex"
        )
    }

    func makeDefault() async throws {
        let workspace = NSWorkspace.shared
        let applicationURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                workspace.setDefaultApplication(
                    at: applicationURL,
                    toOpenURLsWithScheme: scheme
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}
