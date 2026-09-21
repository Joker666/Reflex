import AppKit
import Foundation
import Security
import Testing
@testable import Reflex

@Suite("Phase 1 routing")
struct ReflexTests {
    @Test("Target grouping repairs split browser groups")
    func targetGroupingRepairsSplitBrowserGroups() {
        let chromePersonal = makeTarget(name: "Chrome Personal", bundleIdentifier: "com.google.Chrome")
        let safari = makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let chromeWork = makeTarget(name: "Chrome Work", bundleIdentifier: "com.google.Chrome")

        let result = [chromePersonal, safari, chromeWork].groupingTargetsByBrowser()

        #expect(result.map(\.id) == [chromePersonal.id, chromeWork.id, safari.id])
    }

    @Test("Dragging inside a browser reorders only its profiles")
    func targetMoveReordersProfilesInsideBrowser() {
        let chromePersonal = makeTarget(name: "Chrome Personal", bundleIdentifier: "com.google.Chrome")
        let chromeWork = makeTarget(name: "Chrome Work", bundleIdentifier: "com.google.Chrome")
        let safari = makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari")

        let result = [chromePersonal, chromeWork, safari]
            .movingTarget(chromePersonal.id, over: chromeWork.id)

        #expect(result.map(\.id) == [chromeWork.id, chromePersonal.id, safari.id])
    }

    @Test("Dragging across browsers moves the full browser group")
    func targetMoveKeepsBrowserGroupTogether() {
        let chromePersonal = makeTarget(name: "Chrome Personal", bundleIdentifier: "com.google.Chrome")
        let chromeWork = makeTarget(name: "Chrome Work", bundleIdentifier: "com.google.Chrome")
        let safari = makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let firefox = makeTarget(name: "Firefox", bundleIdentifier: "org.mozilla.firefox")

        let movedDown = [chromePersonal, chromeWork, safari, firefox]
            .movingTarget(chromeWork.id, over: safari.id)
        let movedUp = movedDown.movingTarget(chromePersonal.id, over: safari.id)

        #expect(movedDown.map(\.id) == [safari.id, chromePersonal.id, chromeWork.id, firefox.id])
        #expect(movedUp.map(\.id) == [chromePersonal.id, chromeWork.id, safari.id, firefox.id])
    }

    @Test("Profile validation rejects control characters")
    func profileValidation() {
        #expect(BrowserLauncher.isValidProfileDirectory("Profile 1"))
        #expect(BrowserLauncher.isValidProfileDirectory("Default"))
        #expect(!BrowserLauncher.isValidProfileDirectory(""))
        #expect(!BrowserLauncher.isValidProfileDirectory(".."))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile/1"))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile\\1"))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile\n1"))
        #expect(!BrowserLauncher.isValidProfileDirectory("Profile\u{0000}1"))
    }

    @Test("Profile discovery reads every profile directory and name")
    func profileDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chromeDirectory = root.appending(path: "Google/Chrome", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: chromeDirectory.appending(path: "Default", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: chromeDirectory.appending(path: "Profile 1", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let localState: [String: Any] = [
            "profile": [
                "info_cache": [
                    "Default": ["name": "Private account name"],
                    "Profile 1": ["name": "Another private name"],
                    "Missing": ["name": "Stale profile"],
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: localState)
            .write(to: chromeDirectory.appending(path: "Local State"))
        let edgeDirectory = root.appending(path: "Microsoft Edge", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: edgeDirectory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: edgeDirectory.appending(path: "Local State"))
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Edge", bundleIdentifier: "com.microsoft.edgemac"),
        ]

        let result = BrowserProfileDiscovery(applicationSupportURL: root).discover(for: targets)

        #expect(result.profiles == [
            DiscoveredBrowserProfile(
                browserName: "Chrome",
                bundleIdentifier: "com.google.Chrome",
                profileDirectory: "Default",
                profileName: "Private account name"
            ),
            DiscoveredBrowserProfile(
                browserName: "Chrome",
                bundleIdentifier: "com.google.Chrome",
                profileDirectory: "Profile 1",
                profileName: "Another private name"
            ),
        ])
        #expect(result.accessDeniedBrowserNames.isEmpty)
        #expect(result.missingProfileDataBrowserNames == ["Edge"])
        #expect(result.readableBundleIdentifiers == ["com.google.Chrome"])
    }

    @Test("Profile discovery distinguishes denied access from missing data")
    func profileAccessStates() {
        let target = makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome")

        let denied = BrowserProfileDiscovery(
            dataLoader: { _ in throw CocoaError(.fileReadNoPermission) }
        ).discover(for: [target])
        let missing = BrowserProfileDiscovery(
            dataLoader: { _ in throw CocoaError(.fileReadNoSuchFile) }
        ).discover(for: [target])

        #expect(denied.accessDeniedBrowserNames == ["Chrome"])
        #expect(denied.missingProfileDataBrowserNames.isEmpty)
        #expect(denied.readableBundleIdentifiers.isEmpty)
        #expect(missing.accessDeniedBrowserNames.isEmpty)
        #expect(missing.missingProfileDataBrowserNames == ["Chrome"])
        #expect(missing.readableBundleIdentifiers.isEmpty)
    }

    @Test("A profile name falls back to the account fields")
    func profileNameResolution() {
        #expect(BrowserProfileDiscovery.profileName(
            from: ["name": "Personal"],
            directory: "Default"
        ) == "Personal")
        #expect(BrowserProfileDiscovery.profileName(
            from: ["name": "Profile 2", "gaia_name": "Ayaz"],
            directory: "Profile 2"
        ) == "Ayaz")
        #expect(BrowserProfileDiscovery.profileName(
            from: [
                "name": "Person 1",
                "edge_account_first_name": "MD",
                "edge_account_last_name": "Ahad",
                "gaia_name": "MD Ahad (12345)",
            ],
            directory: "Profile 1"
        ) == "MD Ahad")
        #expect(BrowserProfileDiscovery.profileName(
            from: ["name": "  ", "user_name": "person@example.com"],
            directory: "Profile 3"
        ) == "person@example.com")
        #expect(BrowserProfileDiscovery.profileName(from: [:], directory: "Profile 4") == "Profile 4")
    }

    @Test("A scan replaces a name Reflex made from the directory")
    func profileExpansionReplacesFallbackName() {
        let target = BrowserTarget(
            id: UUID(),
            name: "Microsoft Edge (Profile 1)",
            bundleIdentifier: "com.microsoft.edgemac",
            purpose: "General browsing in Microsoft Edge (Profile 1)",
            chromiumProfileDirectory: "Profile 2",
            isEnabled: true
        )
        let named = BrowserTarget(
            id: UUID(),
            name: "Edge for invoices",
            bundleIdentifier: "com.microsoft.edgemac",
            purpose: "Invoices",
            chromiumProfileDirectory: "Default",
            isEnabled: true
        )
        let profiles = [
            DiscoveredBrowserProfile(
                browserName: "Microsoft Edge",
                bundleIdentifier: "com.microsoft.edgemac",
                profileDirectory: "Default",
                profileName: "Personal"
            ),
            DiscoveredBrowserProfile(
                browserName: "Microsoft Edge",
                bundleIdentifier: "com.microsoft.edgemac",
                profileDirectory: "Profile 2",
                profileName: "Ayaz"
            ),
        ]

        let result = [target, named].expandingProfiles(["com.microsoft.edgemac": profiles])

        #expect(result.count == 2)
        #expect(result[0].name == "Microsoft Edge (Ayaz)")
        #expect(result[0].purpose == "General browsing in Microsoft Edge (Profile 1)")
        #expect(result[1].name == "Edge for invoices")
        #expect(result[1].purpose == "Invoices")
    }

    @Test("Two profiles replace the plain target and keep its purpose")
    func profileExpansionReplacesPlainTarget() {
        let chrome = BrowserTarget(
            id: UUID(),
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Work links",
            chromiumProfileDirectory: nil,
            isEnabled: true
        )
        let safari = makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari")

        let result = [chrome, safari].expandingProfiles([
            "com.google.Chrome": [
                makeProfile(directory: "Default", name: "Personal"),
                makeProfile(directory: "Profile 1", name: "Slumber"),
            ],
        ])

        #expect(result.count == 3)
        #expect(result[0].id == chrome.id)
        #expect(result[0].name == "Google Chrome (Personal)")
        #expect(result[0].chromiumProfileDirectory == "Default")
        #expect(result[0].purpose == "Work links")
        #expect(result[1].name == "Google Chrome (Slumber)")
        #expect(result[1].chromiumProfileDirectory == "Profile 1")
        #expect(result[1].isEnabled)
        #expect(result[2].id == safari.id)
    }

    @Test("A single profile keeps one plain target")
    func singleProfileKeepsPlainTarget() {
        let chrome = makeTarget(name: "Google Chrome", bundleIdentifier: "com.google.Chrome")

        let result = [chrome].expandingProfiles([
            "com.google.Chrome": [makeProfile(directory: "Default", name: "Personal")],
        ])

        #expect(result.count == 1)
        #expect(result[0].id == chrome.id)
        #expect(result[0].name == chrome.name)
        #expect(result[0].purpose == chrome.purpose)
        #expect(result[0].isEnabled == chrome.isEnabled)
        #expect(result[0].chromiumProfileDirectory == "Default")
    }

    @Test("A rescan keeps profile targets and adds new profiles")
    func profileExpansionKeepsConfiguration() {
        let personal = BrowserTarget(
            id: UUID(),
            name: "Chrome Work",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Company links",
            chromiumProfileDirectory: "Default",
            isEnabled: false
        )

        let result = [personal].expandingProfiles([
            "com.google.Chrome": [
                makeProfile(directory: "Default", name: "Personal"),
                makeProfile(directory: "Profile 1", name: "Slumber"),
            ],
        ])

        #expect(result.count == 2)
        #expect(result[0] == personal)
        #expect(result[1].name == "Chrome Work (Slumber)")
        #expect(result[1].chromiumProfileDirectory == "Profile 1")
    }

    @Test("A later multi-profile scan names the former plain target")
    func profileExpansionNamesFormerSingleProfileTarget() {
        var chrome = makeTarget(name: "Google Chrome", bundleIdentifier: "com.google.Chrome")
        chrome.chromiumProfileDirectory = "Default"

        let result = [chrome].expandingProfiles([
            "com.google.Chrome": [
                makeProfile(directory: "Default", name: "Personal"),
                makeProfile(directory: "Profile 1", name: "Slumber"),
            ],
        ])

        #expect(result.count == 2)
        #expect(result[0].id == chrome.id)
        #expect(result[0].name == "Google Chrome (Personal)")
        #expect(result[1].name == "Google Chrome (Slumber)")
    }

    @Test("A profile scan removes targets that are no longer present")
    func profileExpansionRemovesMissingProfiles() {
        let personal = BrowserTarget(
            id: UUID(),
            name: "Google Chrome (Personal)",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Personal links",
            chromiumProfileDirectory: "Default",
            isEnabled: true
        )
        let removed = BrowserTarget(
            id: UUID(),
            name: "Google Chrome (Old)",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Old links",
            chromiumProfileDirectory: "Profile 2",
            isEnabled: true
        )

        let result = [personal, removed].expandingProfiles([
            "com.google.Chrome": [makeProfile(directory: "Default", name: "Personal")],
        ])

        #expect(result == [BrowserTarget(
            id: personal.id,
            name: "Google Chrome",
            bundleIdentifier: personal.bundleIdentifier,
            purpose: personal.purpose,
            chromiumProfileDirectory: "Default",
            isEnabled: personal.isEnabled
        )])
    }

    @Test("An unavailable profile scan returns the browser to one target")
    func profileExpansionCollapsesUnavailableProfiles() {
        let personal = BrowserTarget(
            id: UUID(),
            name: "Google Chrome (Personal)",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Personal links",
            chromiumProfileDirectory: "Default",
            isEnabled: false
        )
        let work = BrowserTarget(
            id: UUID(),
            name: "Google Chrome (Work)",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Work links",
            chromiumProfileDirectory: "Profile 1",
            isEnabled: true
        )

        let result = [personal, work].expandingProfiles(
            [:],
            scannedBundleIdentifiers: ["com.google.Chrome"]
        )

        #expect(result.count == 1)
        #expect(result[0].id == personal.id)
        #expect(result[0].name == "Google Chrome")
        #expect(result[0].purpose == personal.purpose)
        #expect(result[0].chromiumProfileDirectory == nil)
        #expect(!result[0].isEnabled)
    }

    @Test("A profile launch passes the original URL as one argument")
    func profileLaunchArguments() throws {
        let url = try #require(URL(string: "https://example.com/a%20b?q=one two;rm -rf /#frag"))

        let arguments = BrowserLauncher.profileLaunchArguments(
            applicationPath: "/Applications/Google Chrome.app",
            profileDirectory: "Profile 1",
            url: url
        )

        #expect(arguments == [
            "-na",
            "/Applications/Google Chrome.app",
            "--args",
            "--profile-directory=Profile 1",
            url.absoluteString,
        ])
        #expect(arguments.last == url.absoluteString)
    }

    @Test("URL queue advances in FIFO order")
    func queueIsFIFO() {
        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two")!
        let third = URL(string: "https://example.com/three")!
        var queue = PendingURLQueue()

        queue.enqueue(first, sourceApplicationBundleIdentifier: "com.example.first")
        queue.enqueue(second, sourceApplicationBundleIdentifier: "com.example.second")
        queue.enqueue(third)

        #expect(queue.current?.url == first)
        #expect(queue.current?.sourceApplicationBundleIdentifier == "com.example.first")
        #expect(queue.advance()?.url == second)
        #expect(queue.current?.sourceApplicationBundleIdentifier == "com.example.second")
        #expect(queue.advance()?.url == third)
        #expect(queue.advance() == nil)
    }

    @Test("A scan clears the purpose Reflex wrote itself")
    func clearsGeneratedPurposes() {
        let generated = BrowserTarget(
            id: UUID(),
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            purpose: "General browsing in Safari",
            chromiumProfileDirectory: nil,
            isEnabled: true
        )
        let written = BrowserTarget(
            id: UUID(),
            name: "Dia",
            bundleIdentifier: "company.thebrowser.dia",
            purpose: "Reading long articles",
            chromiumProfileDirectory: nil,
            isEnabled: true
        )

        let result = [generated, written].clearingGeneratedPurposes()

        #expect(result[0].purpose.isEmpty)
        #expect(result[1].purpose == "Reading long articles")
    }

    @Test("The queue keeps the request for the chooser")
    func queueKeepsChooserRequest() {
        var queue = PendingURLQueue()
        queue.enqueue(URL(string: "https://example.com/one")!, asksForChooser: true)
        queue.enqueue(URL(string: "https://example.com/two")!)

        #expect(queue.current?.asksForChooser == true)
        #expect(queue.advance()?.asksForChooser == false)
    }

    @Test("Chooser modifier uses Option by default and matches the selected key")
    func chooserModifier() {
        #expect(ChooserModifier.fromStoredValue(nil) == .option)
        #expect(ChooserModifier.fromStoredValue("unknown") == .option)
        #expect(ChooserModifier.fromStoredValue("fn") == .function)
        #expect(ChooserModifier.control.isPressed(in: [.control]))
        #expect(!ChooserModifier.control.isPressed(in: [.option]))
    }

    @Test("Discovery merge keeps configured values")
    func discoveryMergePreservesConfiguration() {
        let id = UUID()
        let configured = BrowserTarget(
            id: id,
            name: "My Work Browser",
            bundleIdentifier: "com.google.Chrome",
            purpose: "Company links",
            chromiumProfileDirectory: "Profile 2",
            isEnabled: false
        )
        let discoveries = [
            DiscoveredBrowser(
                name: "Example Browser",
                bundleIdentifier: "com.google.Chrome",
                applicationURL: URL(fileURLWithPath: "/Applications/Example.app")
            ),
            DiscoveredBrowser(
                name: "Firefox",
                bundleIdentifier: "org.mozilla.firefox",
                applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app")
            ),
        ]

        let result = [configured].mergingDiscoveries(discoveries)

        #expect(result.count == 2)
        #expect(result[0] == configured)
        #expect(result[1].name == "Firefox")
        #expect(result[1].purpose.isEmpty)
        #expect(result[1].isEnabled)
    }

    @Test("Discovery merge removes browsers that are no longer installed")
    func discoveryMergeRemovesUnavailableBrowsers() {
        let installed = makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome")
        let unavailable = makeTarget(name: "Firefox", bundleIdentifier: "org.mozilla.firefox")
        let discoveries = [
            DiscoveredBrowser(
                name: "Chrome",
                bundleIdentifier: "com.google.Chrome",
                applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
            ),
        ]

        let result = [installed, unavailable].mergingDiscoveries(discoveries)

        #expect(result == [installed])
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

    @Test("Settings close keeps the menu bar process running")
    func settingsClosePolicy() {
        #expect(!SettingsWindowController.shouldTerminateOnClose(
            showsMenuBarItem: true,
            hasPendingURL: false
        ))
        #expect(!SettingsWindowController.shouldTerminateOnClose(
            showsMenuBarItem: false,
            hasPendingURL: true
        ))
        #expect(SettingsWindowController.shouldTerminateOnClose(
            showsMenuBarItem: false,
            hasPendingURL: false
        ))
    }

    @Test("Discovery uses the HTTP and HTTPS union and keeps only supported browsers")
    func discoveryUnionDeduplicationAndSelfExclusion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reflex = try makeApplication(at: root, name: "Reflex", identifier: "com.example.Reflex")
        let safari = try makeApplication(at: root, name: "Safari", identifier: "com.apple.Safari")
        let firefox = try makeApplication(at: root, name: "Firefox", identifier: "org.mozilla.firefox")
        let chat = try makeApplication(at: root, name: "ChatGPT", identifier: "com.openai.chat")
        let query = FakeBrowserQuery(http: [reflex, safari, chat], https: [safari, firefox])

        let result = BrowserDiscovery(
            query: query,
            selfBundleIdentifier: "com.example.Reflex"
        ).discover()

        #expect(result.map(\.bundleIdentifier) == ["org.mozilla.firefox", "com.apple.Safari"])
    }

    @Test("Supported target filter removes other applications")
    func supportedTargetFilter() {
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "ChatGPT", bundleIdentifier: "com.openai.chat"),
            makeTarget(
                name: "My renamed browser",
                bundleIdentifier: "/Applications/Zen Browser.app"
            ),
            makeTarget(
                name: "Unsupported path app",
                bundleIdentifier: "/Applications/ChatGPT.app"
            ),
        ]

        #expect(
            targets.filter(BrowserDiscovery.isSupportedTarget).map(\.name)
                == ["Chrome", "My renamed browser"]
        )
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
        let targets = [
            BrowserTarget(
                id: UUID(),
                name: "Work",
                bundleIdentifier: "com.example.work",
                purpose: "",
                chromiumProfileDirectory: nil,
                isEnabled: true
            ),
            makeTarget(name: "Personal"),
        ]
        let context = RoutingContext(
            scheme: "https",
            host: "example.com",
            path: "/item",
            queryParameterNames: ["token"],
            sourceApplicationBundleIdentifier: "com.tinyspeck.slackmacgap",
            sourceApplicationName: "Slack"
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
        #expect(state["sourceApplicationName"] as? String == "Slack")
        let questions = try #require(object["questions"] as? [String: Any])
        let question = try #require(questions["target"] as? [String: Any])
        let criteria = try #require(question["criteria"] as? [String: String])
        // A target without a purpose says so, instead of sending an empty line.
        #expect(criteria["target_0"]?.contains("no purpose") == true)
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

    @Test("Timeout and network errors use the chooser fallback", arguments: [
        URLError.Code.timedOut,
        URLError.Code.notConnectedToInternet,
    ])
    func failureFallback(errorCode: URLError.Code) async throws {
        let targets = [makeTarget(), makeTarget()]
        let context = RoutingContext(
            scheme: "https",
            host: "example.com",
            path: "/",
            queryParameterNames: [],
            sourceApplicationBundleIdentifier: nil
        )
        let client = JevClient(transport: FailingJevTransport(errorCode: errorCode))
        var decision: RouteDecision?

        do {
            decision = try await client.decide(context: context, targets: targets, apiKey: "test-key")
            Issue.record("The transport error did not propagate.")
        } catch let error as URLError {
            #expect(error.code == errorCode)
        }

        #expect(RoutingPolicy.action(availableTargets: targets, decision: decision) == .choose(suggestedTargetID: nil))
    }

    @Test("App state uses its injected routing services")
    @MainActor
    func appStateUsesInjectedRoutingServices() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        let recorder = BrowserOpenRecorder()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: FirstTargetJevDecider(),
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )

        state.receive([URL(string: "https://example.com")!])
        for _ in 0..<100 {
            if await recorder.targetID != nil { break }
            await Task.yield()
        }

        #expect(await recorder.targetID == targets[0].id)
        #expect(state.pendingURL == nil)
    }

    @Test("Toggling usesJev to false bypasses Jev and does not auto-open")
    @MainActor
    func usesJevToggleBypassesJev() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        defaults.set(false, forKey: "usesJev")
        let recorder = BrowserOpenRecorder()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: FirstTargetJevDecider(),
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )
        #expect(!state.usesJev)

        state.receive([URL(string: "https://example.com")!])
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(await recorder.targetID == nil)
        #expect(state.pendingURL != nil)
        #expect(state.suggestedTargetID == nil)

        state.usesJev = true
        for _ in 0..<100 {
            if await recorder.targetID != nil { break }
            await Task.yield()
        }

        #expect(await recorder.targetID == targets[0].id)
        #expect(state.pendingURL == nil)
    }

    @Test("Turning off usesJev while Jev request is active cancels routing and keeps pending link in chooser")
    @MainActor
    func turningOffUsesJevWhileRoutingCancelsActiveTask() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        defaults.set(true, forKey: "usesJev")
        let recorder = BrowserOpenRecorder()
        let decider = ControllableJevDecider()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: decider,
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )
        #expect(state.usesJev)

        state.receive([URL(string: "https://example.com")!])
        await decider.waitUntilStarted()
        #expect(state.isRouting)
        #expect(state.pendingURL != nil)

        // Switch off automatic selection while the Jev request is active
        state.usesJev = false

        #expect(!state.isRouting)
        #expect(state.pendingURL != nil)
        #expect(state.suggestedTargetID == nil)

        // Complete the in-flight request with high confidence
        await decider.complete(targetID: targets[0].id, confidence: 1.0)
        for _ in 0..<20 {
            await Task.yield()
        }

        // Must NOT auto-open; must remain in the chooser
        #expect(await recorder.targetID == nil)
        #expect(state.pendingURL != nil)
        #expect(state.suggestedTargetID == nil)
    }

    @Test("An old Jev decision cannot route the next link")
    @MainActor
    func staleJevDecisionCannotRouteNextLink() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        let decider = ControlledJevDecider()
        let recorder = BrowserOpenRecorder()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: decider,
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )
        let firstURL = URL(string: "https://first.example/path")!
        let secondURL = URL(string: "https://second.example/path")!

        state.receive([firstURL, secondURL])
        for _ in 0..<100 {
            if await decider.hasRequest(for: "first.example") { break }
            await Task.yield()
        }
        state.cancelPending()
        for _ in 0..<100 {
            if await decider.hasRequest(for: "second.example") { break }
            await Task.yield()
        }

        await decider.resume(
            host: "first.example",
            decision: RouteDecision(targetID: targets[0].id, confidence: 1)
        )
        await Task.yield()
        #expect(state.pendingURL == secondURL)
        #expect(await recorder.targetID == nil)

        await decider.resume(
            host: "second.example",
            decision: RouteDecision(targetID: targets[1].id, confidence: 1)
        )
        for _ in 0..<100 {
            if state.pendingURL == nil { break }
            await Task.yield()
        }

        #expect(await recorder.targetID == targets[1].id)
        #expect(state.pendingURL == nil)
    }

    @Test("A Jev decision cannot open a target removed while routing")
    @MainActor
    func jevDecisionUsesCurrentTargets() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            makeTarget(name: "Firefox", bundleIdentifier: "org.mozilla.firefox"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        let decider = ControlledJevDecider()
        let recorder = BrowserOpenRecorder()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: decider,
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )

        state.receive([URL(string: "https://example.com/path")!])
        for _ in 0..<100 {
            if await decider.hasRequest(for: "example.com") { break }
            await Task.yield()
        }
        state.removeTarget(id: targets[0].id)
        await decider.resume(
            host: "example.com",
            decision: RouteDecision(targetID: targets[0].id, confidence: 1)
        )
        for _ in 0..<20 { await Task.yield() }

        #expect(await recorder.targetID == nil)
        #expect(state.pendingURL != nil)
        #expect(state.suggestedTargetID == nil)
    }

    @Test("Opening Settings pauses the next queued link")
    @MainActor
    func settingsPauseQueuedRouting() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targets = [
            makeTarget(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
            makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ]
        defaults.set(try JSONEncoder().encode(targets), forKey: "browserTargets")
        let decider = ControlledJevDecider()
        let recorder = BrowserOpenRecorder()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: "test-key"),
            launcher: RecordingBrowserLauncher(recorder: recorder),
            jevClient: decider,
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )
        let firstURL = URL(string: "https://first.example/path")!
        let secondURL = URL(string: "https://second.example/path")!

        state.receive([firstURL, secondURL])
        for _ in 0..<100 {
            if await decider.hasRequest(for: "first.example") { break }
            await Task.yield()
        }
        state.openSettings()
        await decider.resume(
            host: "first.example",
            decision: RouteDecision(targetID: targets[0].id, confidence: 1)
        )
        for _ in 0..<20 { await Task.yield() }

        #expect(state.pendingURL == secondURL)
        #expect(!(await decider.hasRequest(for: "second.example")))
        #expect(await recorder.targetID == nil)

        state.settingsDidClose()
        for _ in 0..<100 {
            if await decider.hasRequest(for: "second.example") { break }
            await Task.yield()
        }
        #expect(await decider.hasRequest(for: "second.example"))
        await decider.resume(
            host: "second.example",
            decision: RouteDecision(targetID: targets[0].id, confidence: 0)
        )
        for _ in 0..<20 { await Task.yield() }
        #expect(state.pendingURL == secondURL)
    }

    @Test("An old browser launch cannot advance the next link")
    @MainActor
    func staleBrowserLaunchCannotAdvanceNextLink() async throws {
        let suiteName = "ReflexTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let target = makeTarget(name: "Safari", bundleIdentifier: "com.apple.Safari")
        defaults.set(try JSONEncoder().encode([target]), forKey: "browserTargets")
        let launcherState = ControlledBrowserLauncherState()
        let state = AppState(
            keychain: TestKeychainStore(apiKey: nil),
            launcher: ControlledBrowserLauncher(state: launcherState),
            jevClient: FirstTargetJevDecider(),
            defaults: defaults,
            browserScanner: FixedBrowserScanner(),
            defaultBrowserService: FixedDefaultBrowserService()
        )
        let firstURL = URL(string: "https://first.example/path")!
        let secondURL = URL(string: "https://second.example/path")!

        state.receive([firstURL, secondURL])
        for _ in 0..<100 {
            if await launcherState.hasRequest(for: "first.example") { break }
            await Task.yield()
        }
        state.cancelPending()
        for _ in 0..<100 {
            if await launcherState.hasRequest(for: "second.example") { break }
            await Task.yield()
        }

        await launcherState.resume(host: "first.example")
        await Task.yield()
        #expect(state.pendingURL == secondURL)

        await launcherState.resume(host: "second.example")
        for _ in 0..<100 {
            if state.pendingURL == nil { break }
            await Task.yield()
        }

        #expect(state.pendingURL == nil)
    }

    @Test("AppleEventSender extracts sender bundle identifier from sender PID or audit token, ignoring target address")
    func appleEventSenderResolution() throws {
        #expect(AppleEventSender.bundleIdentifier(from: nil) == nil)

        let pidEvent = MockAppleEventDescriptor()
        var pid: pid_t = 4242
        let pidDesc = try #require(
            NSAppleEventDescriptor(
                descriptorType: DescType(typeKernelProcessID),
                data: Data(bytes: &pid, count: MemoryLayout<pid_t>.size)
            )
        )
        pidEvent.attributes[keySenderPIDAttr] = pidDesc

        let resolved = AppleEventSender.bundleIdentifier(from: pidEvent) { queryPID in
            queryPID == 4242 ? "com.tinyspeck.slackmacgap" : nil
        }
        #expect(resolved == "com.tinyspeck.slackmacgap")

        // Sender audit token attribute
        let auditEvent = MockAppleEventDescriptor()
        var token = audit_token_t(val: (0, 0, 0, 0, 0, 4243, 0, 0))
        let auditDesc = try #require(
            NSAppleEventDescriptor(
                descriptorType: DescType(typeWildCard),
                data: Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
            )
        )
        auditEvent.attributes[keySenderAuditTokenAttr] = auditDesc
        let resolvedAudit = AppleEventSender.bundleIdentifier(from: auditEvent) { queryPID in
            queryPID == 4243 ? "com.tinyspeck.slackmacgap" : nil
        }
        #expect(resolvedAudit == "com.tinyspeck.slackmacgap")

        // Target address attributes must NOT be used as sender fallback
        let target = NSAppleEventDescriptor.null()
        let targetAddrEvent = try #require(
            NSAppleEventDescriptor.appleEvent(
                withEventClass: AEEventClass(kInternetEventClass),
                eventID: AEEventID(kAEGetURL),
                targetDescriptor: target,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID)
            )
        )
        targetAddrEvent.setAttribute(pidDesc, forKeyword: keyAddressAttr)
        let targetAddrResolved = AppleEventSender.bundleIdentifier(from: targetAddrEvent) { _ in
            "com.rafi.Reflex"
        }
        #expect(targetAddrResolved == nil)

        let unknown = AppleEventSender.bundleIdentifier(from: pidEvent) { _ in nil }
        #expect(unknown == nil)
    }

    @Test("Keychain store error provides localized error descriptions")
    func keychainStoreErrorDescription() {
        let error = KeychainStoreError.unexpectedStatus(errSecAuthFailed)
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)

        let customError = KeychainStoreError.unexpectedStatus(-99999)
        #expect(customError.errorDescription?.contains("-99999") == true)
    }

    @Test("URL helper accurately identifies HTTP and HTTPS schemes")
    func urlHTTPValidation() {
        #expect(URL(string: "http://example.com")!.isHTTPOrHTTPS)
        #expect(URL(string: "https://example.com/test")!.isHTTPOrHTTPS)
        #expect(URL(string: "HTTP://EXAMPLE.COM")!.isHTTPOrHTTPS)
        #expect(!URL(string: "ftp://example.com")!.isHTTPOrHTTPS)
        #expect(!URL(string: "file:///path/to/file")!.isHTTPOrHTTPS)
    }

    @Test("Bundle display name helper resolves display name or falls back to URL name")
    func bundleDisplayNameHelper() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApplication(at: root, name: "CustomBrowser", identifier: "com.example.custom")
        let bundle = try #require(Bundle(url: app))
        #expect(bundle.displayName(fallbackURL: app) == "CustomBrowser")
    }

    @Test("SupportedBrowser correctly classifies browsers and Chromium profile paths")
    func supportedBrowserClassification() {
        #expect(SupportedBrowser.matching(bundleIdentifier: "com.google.Chrome") == .chrome)
        #expect(SupportedBrowser.matching(bundleIdentifier: "com.google.Chrome.canary") == .chrome)
        #expect(SupportedBrowser.chromiumProfileDataDirectory(for: "com.google.Chrome") == "Google/Chrome")
        #expect(SupportedBrowser.chromiumProfileDataDirectory(for: "com.google.Chrome.canary") == nil)
        #expect(SupportedBrowser.chromiumProfileDataDirectory(for: "com.apple.Safari") == nil)
        #expect(SupportedBrowser.matching(name: "Zen Browser", bundleIdentifier: "unknown") == .zen)
        #expect(SupportedBrowser.matching(name: "Random Browser", bundleIdentifier: "com.unknown.browser") == nil)
        #expect(
            SupportedBrowser.selectionInstruction
                == "Select Safari, Chrome, Dia, Comet, Helium, Edge, Phi, Zen, or Firefox."
        )
    }

    @Test("AppVersion formats short version and build number")
    func appVersionFormatting() {
        #expect(AppVersion.formatted(shortVersion: "0.1.0", buildVersion: "3") == "Version 0.1.0")
        #expect(AppVersion.formatted(shortVersion: "1.2", buildVersion: nil) == "Version 1.2")
        #expect(AppVersion.formatted(shortVersion: nil, buildVersion: "42") == "Version 42")
        #expect(AppVersion.formatted(shortVersion: "", buildVersion: "42") == "Version 42")
        #expect(AppVersion.formatted(shortVersion: nil, buildVersion: nil) == nil)
        #expect(AppVersion.formatted(shortVersion: "", buildVersion: "") == nil)
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

    private func makeTarget(
        name: String = "Browser",
        bundleIdentifier: String = "com.example.\(UUID().uuidString)"
    ) -> BrowserTarget {
        BrowserTarget(
            id: UUID(),
            name: name,
            bundleIdentifier: bundleIdentifier,
            purpose: "Test browsing",
            chromiumProfileDirectory: nil,
            isEnabled: true
        )
    }
}

private func makeProfile(directory: String, name: String) -> DiscoveredBrowserProfile {
    DiscoveredBrowserProfile(
        browserName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        profileDirectory: directory,
        profileName: name
    )
}

private struct FakeBrowserQuery: BrowserApplicationQuerying {
    var http: [URL]
    var https: [URL]

    func applicationURLs(toOpen url: URL) -> [URL] {
        url.scheme == "http" ? http : https
    }
}

private struct FailingJevTransport: JevTransport {
    var errorCode: URLError.Code

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(errorCode)
    }
}

private struct TestKeychainStore: APIKeyStoring {
    var apiKey: String?

    func saveAPIKey(_ key: String) throws {}
    func readAPIKey() throws -> String? { apiKey }
    func removeAPIKey() throws {}
}

private actor BrowserOpenRecorder {
    private(set) var targetID: UUID?

    func record(_ targetID: UUID) {
        self.targetID = targetID
    }
}

private actor ControlledJevDecider: JevDeciding {
    private var continuations: [String: CheckedContinuation<RouteDecision, Error>] = [:]

    func decide(
        context: RoutingContext,
        targets: [BrowserTarget],
        apiKey: String
    ) async throws -> RouteDecision {
        try await withCheckedThrowingContinuation { continuation in
            continuations[context.host] = continuation
        }
    }

    func hasRequest(for host: String) -> Bool {
        continuations[host] != nil
    }

    func resume(host: String, decision: RouteDecision) {
        continuations.removeValue(forKey: host)?.resume(returning: decision)
    }
}

private actor ControlledBrowserLauncherState {
    private var continuations: [String: CheckedContinuation<Void, Error>] = [:]

    func open(_ url: URL) async throws {
        let host = url.host() ?? ""
        try await withCheckedThrowingContinuation { continuation in
            continuations[host] = continuation
        }
    }

    func hasRequest(for host: String) -> Bool {
        continuations[host] != nil
    }

    func resume(host: String) {
        continuations.removeValue(forKey: host)?.resume()
    }
}

private struct ControlledBrowserLauncher: BrowserLaunching {
    var state: ControlledBrowserLauncherState

    func isAvailable(_ target: BrowserTarget) -> Bool { true }
    func icon(for target: BrowserTarget) -> NSImage? { nil }

    func open(_ originalURL: URL, in target: BrowserTarget) async throws {
        try await state.open(originalURL)
    }
}

private struct RecordingBrowserLauncher: BrowserLaunching {
    var recorder: BrowserOpenRecorder

    func isAvailable(_ target: BrowserTarget) -> Bool { true }
    func icon(for target: BrowserTarget) -> NSImage? { nil }

    func open(_ originalURL: URL, in target: BrowserTarget) async throws {
        await recorder.record(target.id)
    }
}

private struct FirstTargetJevDecider: JevDeciding {
    func decide(
        context: RoutingContext,
        targets: [BrowserTarget],
        apiKey: String
    ) async throws -> RouteDecision {
        RouteDecision(targetID: targets[0].id, confidence: 1)
    }
}

private actor ControllableJevDecider: JevDeciding {
    private var continuation: CheckedContinuation<RouteDecision, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func decide(
        context: RoutingContext,
        targets: [BrowserTarget],
        apiKey: String
    ) async throws -> RouteDecision {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                hasStarted = true
                startedContinuation?.resume()
                startedContinuation = nil
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { cont in
            startedContinuation = cont
        }
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func complete(targetID: UUID, confidence: Double = 1.0) {
        continuation?.resume(returning: RouteDecision(targetID: targetID, confidence: confidence))
        continuation = nil
    }
}

private struct FixedBrowserScanner: BrowserScanning {
    func scan(existingTargets: [BrowserTarget]) async -> BrowserScanResult {
        BrowserScanResult(
            discoveries: [],
            profiles: BrowserProfileDiscoveryResult(
                profiles: [],
                accessDeniedBrowserNames: [],
                missingProfileDataBrowserNames: []
            )
        )
    }
}

private struct FixedDefaultBrowserService: DefaultBrowserServicing {
    func currentStatus() -> DefaultBrowserStatus {
        DefaultBrowserStatus(ownsHTTP: false, ownsHTTPS: false)
    }

    func makeDefault() async throws {}
}

private final class MockAppleEventDescriptor: NSAppleEventDescriptor {
    var attributes: [AEKeyword: NSAppleEventDescriptor] = [:]
    override func attributeDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor? {
        attributes[keyword]
    }
}
