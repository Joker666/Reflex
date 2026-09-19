import Foundation
import Testing
@testable import Reflex

@Suite("Phase 1 routing")
struct ReflexTests {
    @Test("Profile validation rejects control characters")
    func profileValidation() {
        #expect(BrowserLauncher.isValidProfileDirectory("Profile 1"))
        #expect(BrowserLauncher.isValidProfileDirectory("Default"))
        #expect(!BrowserLauncher.isValidProfileDirectory(""))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile\n1"))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile\u{0000}1"))
    }

    @Test("URL queue advances in FIFO order")
    func queueIsFIFO() {
        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two")!
        let third = URL(string: "https://example.com/three")!
        var queue = PendingURLQueue()

        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)

        #expect(queue.current == first)
        #expect(queue.advance() == second)
        #expect(queue.advance() == third)
        #expect(queue.advance() == nil)
    }

    @Test("Discovery merge keeps configured values")
    func discoveryMergePreservesConfiguration() {
        let id = UUID()
        let configured = BrowserTarget(
            id: id,
            name: "My Work Browser",
            bundleIdentifier: "com.example.browser",
            purpose: "Company links",
            chromiumProfileDirectory: "Profile 2",
            isEnabled: false
        )
        let discoveries = [
            DiscoveredBrowser(
                name: "Example Browser",
                bundleIdentifier: "com.example.browser",
                applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
            ),
            DiscoveredBrowser(
                name: "New Browser",
                bundleIdentifier: "com.example.new",
                applicationURL: URL(fileURLWithPath: "/Applications/New.app")
            ),
        ]

        let result = [configured].mergingDiscoveries(discoveries)

        #expect(result.count == 2)
        #expect(result[0] == configured)
        #expect(result[1].name == "New Browser")
        #expect(result[1].purpose == "General browsing in New Browser")
        #expect(result[1].isEnabled)
    }

    @Test("Default status requires both schemes")
    func defaultStatusRequiresBothSchemes() {
        let identifier = "com.example.Reflex"
        #expect(DefaultBrowserService.status(
            defaultHTTPBundleIdentifier: identifier,
            defaultHTTPSBundleIdentifier: identifier,
            reflexBundleIdentifier: identifier
        ).isComplete)
        #expect(!DefaultBrowserService.status(
            defaultHTTPBundleIdentifier: identifier,
            defaultHTTPSBundleIdentifier: "com.example.other",
            reflexBundleIdentifier: identifier
        ).isComplete)
    }

    @Test("Discovery uses the HTTP and HTTPS union, removes duplicates, and excludes Reflex")
    func discoveryUnionDeduplicationAndSelfExclusion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reflex = try makeApplication(at: root, name: "Reflex", identifier: "com.example.Reflex")
        let alpha = try makeApplication(at: root, name: "Alpha", identifier: "com.example.alpha")
        let beta = try makeApplication(at: root, name: "Beta", identifier: "com.example.beta")
        let query = FakeBrowserQuery(http: [reflex, alpha], https: [alpha, beta])

        let result = BrowserDiscovery(
            query: query,
            selfBundleIdentifier: "com.example.Reflex"
        ).discover()

        #expect(result.map(\.bundleIdentifier) == ["com.example.alpha", "com.example.beta"])
    }

    @Test("URL sanitization removes fragment and query values")
    func urlSanitization() throws {
        let url = try #require(URL(string: "https://Example.com/a%20path?token=secret&mode=fast&token=other#private"))
        let context = try #require(URLSanitizer.sanitize(
            url,
            sourceApplicationBundleIdentifier: "com.example.source"
        ))

        #expect(context.scheme == "https")
        #expect(context.host == "Example.com")
        #expect(context.path == "/a path")
        #expect(context.queryParameterNames == ["token", "mode"])
        #expect(context.sourceApplicationBundleIdentifier == "com.example.source")
        let encoded = String(data: try JSONEncoder().encode(context), encoding: .utf8)!
        #expect(!encoded.contains("secret"))
        #expect(!encoded.contains("private"))
    }

    @Test("Routing policy uses the confidence threshold")
    func routingThreshold() {
        let targets = [makeTarget(), makeTarget()]

        #expect(RoutingPolicy.action(
            availableTargets: targets,
            decision: RouteDecision(targetID: targets[0].id, confidence: 0.849)
        ) == .choose(suggestedTargetID: targets[0].id))
        #expect(RoutingPolicy.action(
            availableTargets: targets,
            decision: RouteDecision(targetID: targets[0].id, confidence: 0.85)
        ) == .open(targets[0].id))
        #expect(RoutingPolicy.action(
            availableTargets: targets,
            decision: RouteDecision(targetID: targets[0].id, confidence: 0.95)
        ) == .open(targets[0].id))
    }

    @Test("Single and zero target policy does not call Jev")
    func localTargetPolicy() {
        let target = makeTarget()
        #expect(RoutingPolicy.action(availableTargets: [], decision: nil) == .setup)
        #expect(RoutingPolicy.action(availableTargets: [target], decision: nil) == .open(target.id))
    }

    @Test("Jev request uses stable local keys and contains no query values")
    func jevRequestEncoding() throws {
        let targets = [makeTarget(name: "Work"), makeTarget(name: "Personal")]
        let context = RoutingContext(
            scheme: "https",
            host: "example.com",
            path: "/item",
            queryParameterNames: ["token"],
            sourceApplicationBundleIdentifier: nil
        )
        let (request, mapping) = try JevClient().makeRequest(
            context: context,
            targets: targets,
            apiKey: "test-key"
        )
        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(object["state"] as? [String: Any])
        let requestTargets = try #require(state["targets"] as? [[String: Any]])
        let encoded = String(data: data, encoding: .utf8)!

        #expect(request.url == JevClient.openRouterEndpoint)
        #expect(object["model"] as? String == "~typesafe/jev-latest")
        #expect(requestTargets.compactMap { $0["key"] as? String } == ["target_0", "target_1"])
        #expect(mapping.keyToTargetID["target_0"] == targets[0].id)
        #expect(mapping.keyToTargetID["target_1"] == targets[1].id)
        #expect(!encoded.contains("queryValue"))
    }

    @Test("Jev response accepts valid choices and rejects invalid answers")
    func jevResponseValidation() throws {
        let target = makeTarget()
        let mapping = JevChoiceMapping(keyToTargetID: ["target_0": target.id])
        let client = JevClient()
        let valid = Data(#"{"answers":{"target":{"choice":"target_0","probabilities":{"target_0":1.0},"confidence":0.9}}}"#.utf8)
        let unknown = Data(#"{"answers":{"target":{"choice":"target_9","probabilities":{"target_9":1.0},"confidence":0.9}}}"#.utf8)
        let missingConfidence = Data(#"{"answers":{"target":{"choice":"target_0","probabilities":{"target_0":1.0}}}}"#.utf8)
        let badConfidence = Data(#"{"answers":{"target":{"choice":"target_0","probabilities":{"target_0":1.0},"confidence":2.0}}}"#.utf8)

        #expect(try client.decodeDecision(valid, mapping: mapping) == RouteDecision(targetID: target.id, confidence: 0.9))
        #expect(throws: JevClientError.invalidResponse) { try client.decodeDecision(unknown, mapping: mapping) }
        #expect(throws: JevClientError.invalidResponse) { try client.decodeDecision(missingConfidence, mapping: mapping) }
        #expect(throws: JevClientError.invalidResponse) { try client.decodeDecision(badConfidence, mapping: mapping) }
    }

    @Test("Timeout and network errors use the chooser fallback")
    func failureFallback() {
        let targets = [makeTarget(), makeTarget()]
        let timeoutDecision: RouteDecision? = nil
        let networkFailureDecision: RouteDecision? = nil

        #expect(RoutingPolicy.action(availableTargets: targets, decision: timeoutDecision) == .choose(suggestedTargetID: nil))
        #expect(RoutingPolicy.action(availableTargets: targets, decision: networkFailureDecision) == .choose(suggestedTargetID: nil))
    }

    private func makeApplication(at root: URL, name: String, identifier: String) throws -> URL {
        let applicationURL = root.appending(path: "\(name).app")
        let contentsURL = applicationURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
        return applicationURL
    }

    private func makeTarget(name: String = "Browser") -> BrowserTarget {
        BrowserTarget(
            id: UUID(),
            name: name,
            bundleIdentifier: "com.example.\(UUID().uuidString)",
            purpose: "Test browsing",
            chromiumProfileDirectory: nil,
            isEnabled: true
        )
    }
}

private struct FakeBrowserQuery: BrowserApplicationQuerying {
    var http: [URL]
    var https: [URL]

    func applicationURLs(toOpen url: URL) -> [URL] {
        url.scheme == "http" ? http : https
    }
}
