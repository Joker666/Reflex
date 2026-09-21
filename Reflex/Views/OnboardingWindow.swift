import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        state.onboardingDidOpen()
        state.refreshDefaultBrowserStatus()
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        let rootView = OnboardingView(state: state) { [weak self] in
            self?.finish()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Welcome to Reflex"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func finish() {
        state.completeOnboarding()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard state.hasCompletedOnboarding else {
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }
        DispatchQueue.main.async {
            let shouldTerminate = SettingsWindowController.shouldTerminateOnClose(
                showsMenuBarItem: self.state.showsMenuBarItem,
                hasPendingURL: self.state.pendingURL != nil
            )
            guard shouldTerminate else {
                NSApplication.shared.setActivationPolicy(.accessory)
                return
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case defaultBrowser
    case profileAccess
    case automaticRouting
    case browsers
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .defaultBrowser: "Default Browser"
        case .profileAccess: "Profile Access"
        case .automaticRouting: "Automatic Routing"
        case .browsers: "Browsers"
        case .ready: "Ready"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "arrow.triangle.branch"
        case .defaultBrowser: "link"
        case .profileAccess: "person.crop.circle.badge.checkmark"
        case .automaticRouting: "sparkles"
        case .browsers: "globe"
        case .ready: "checkmark"
        }
    }
}

struct OnboardingPurposeSuggestion: Identifiable, Equatable {
    let title: String
    let symbol: String
    let purpose: String

    var id: String { title }

    static let all = [
        OnboardingPurposeSuggestion(
            title: "Work",
            symbol: "briefcase",
            purpose: "Work accounts, GitHub, Linear, company mail, and internal tools"
        ),
        OnboardingPurposeSuggestion(
            title: "Personal",
            symbol: "person",
            purpose: "Personal accounts, reading, shopping, banking, and travel"
        ),
        OnboardingPurposeSuggestion(
            title: "Development",
            symbol: "hammer",
            purpose: "Local development, documentation, testing, and technical links"
        ),
        OnboardingPurposeSuggestion(
            title: "Research",
            symbol: "book",
            purpose: "Research, long-form reading, papers, and reference material"
        ),
        OnboardingPurposeSuggestion(
            title: "Media",
            symbol: "play.rectangle",
            purpose: "Video, music, social media, and entertainment"
        ),
    ]

    static func ordered(for targetName: String) -> [OnboardingPurposeSuggestion] {
        let name = targetName.lowercased()
        let preferredTitle: String?
        if name.contains("work") {
            preferredTitle = "Work"
        } else if name.contains("personal") || name.contains("home") {
            preferredTitle = "Personal"
        } else if name.contains("dev") {
            preferredTitle = "Development"
        } else {
            preferredTitle = nil
        }
        guard let preferredTitle,
              let preferred = all.first(where: { $0.title == preferredTitle }) else {
            return all
        }
        return [preferred] + all.filter { $0.id != preferred.id }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: AppState
    let onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var apiKey = ""
    @State private var apiKeyMessage: String?
    @State private var diaAutomationState: AutomationPermissionState = .notDetermined
    @State private var isRequestingDiaAccess = false
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                navigationBar
            }
            .background(.background)
        }
        .frame(width: 820, height: 620)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reflex")
                        .font(.title2.weight(.semibold))
                    Text("Set up your link router")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 34)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(OnboardingStep.allCases) { item in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(step.rawValue >= item.rawValue ? Color.accentColor : Color.secondary.opacity(0.14))
                                .frame(width: 26, height: 26)
                            Image(systemName: step.rawValue > item.rawValue ? "checkmark" : item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(step.rawValue >= item.rawValue ? .white : .secondary)
                        }
                        Text(item.title)
                            .font(.system(size: 13, weight: step == item ? .semibold : .regular))
                            .foregroundStyle(step.rawValue >= item.rawValue ? .primary : .secondary)
                    }
                    .frame(height: 32)
                    .accessibilityLabel("Step \(item.rawValue + 1), \(item.title)")
                    .accessibilityValue(step == item ? "Current" : (step.rawValue > item.rawValue ? "Complete" : "Not started"))
                }
            }
            Spacer()
            Text("Your settings stay on this Mac. Reflex sends reduced link information to OpenRouter only when you enable automatic routing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 42)
        .padding(.bottom, 24)
        .frame(width: 238)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .defaultBrowser: defaultBrowserStep
        case .profileAccess: profileAccessStep
        case .automaticRouting: automaticRoutingStep
        case .browsers: browsersStep
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        OnboardingPage(
            eyebrow: "WELCOME TO REFLEX",
            title: "Every link, in the right place.",
            detail: "Reflex becomes your macOS web-link handler. It can choose a browser or profile automatically, or show a compact chooser when you want control."
        ) {
            VStack(spacing: 14) {
                OnboardingFeature(
                    symbol: "arrow.triangle.branch",
                    title: "Route by intent",
                    detail: "Send work, personal, research, and development links to the correct browser context."
                )
                OnboardingFeature(
                    symbol: "hand.tap",
                    title: "Stay in control",
                    detail: "Hold your chooser modifier when you click a link to select the destination yourself."
                )
                OnboardingFeature(
                    symbol: "lock.shield",
                    title: "Private by design",
                    detail: "Reflex keeps no link history and removes query values and fragments before an automatic decision."
                )
            }
        }
    }

    private var defaultBrowserStep: some View {
        OnboardingPage(
            eyebrow: "REQUIRED FOR EXTERNAL LINKS",
            title: "Make Reflex your default browser.",
            detail: "This lets macOS send HTTP and HTTPS links from other applications to Reflex. You can still open every link in the browser you choose."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                statusCard(
                    isComplete: state.defaultBrowserStatus.isComplete,
                    completeText: "Reflex handles HTTP and HTTPS links",
                    incompleteText: "Another app handles some web links"
                )
                HStack(spacing: 10) {
                    Button("Make Reflex Default Browser") { state.makeDefaultBrowser() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.defaultBrowserStatus.isComplete)
                    Button("Check Again") { state.refreshDefaultBrowserStatus() }
                }
                if let message = state.setupMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("You can continue before this is complete. Reflex will remain available in Settings, but external link clicks will not reach it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var profileAccessStep: some View {
        OnboardingPage(
            eyebrow: "PROFILE DISCOVERY",
            title: "Let Reflex find browser profiles.",
            detail: "Reflex reads only profile directories and profile labels. It does not read history, cookies, passwords, or page data."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if state.isBrowserScanInProgress {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Checking installed browsers and profile access…")
                            .font(.callout)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                } else if !state.profileAccessDeniedBrowsers.isEmpty {
                    statusCard(
                        isComplete: false,
                        completeText: "Profile access is available",
                        incompleteText: "macOS blocks profiles for \(state.profileAccessDeniedBrowsers.joined(separator: ", "))"
                    )
                    Button("Open Full Disk Access") { state.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                    Text("Add Reflex and switch it on. Then return here and select Check Again. macOS does not provide a direct permission request for this access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    statusCard(
                        isComplete: true,
                        completeText: "No profile access problem was found",
                        incompleteText: "Profile access is not available"
                    )
                }

                if !state.missingProfileDataBrowsers.isEmpty {
                    Label(
                        "No profile data was found for \(state.missingProfileDataBrowsers.joined(separator: ", ")). Start each browser once if you want its profiles.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button("Check Again") { state.rescanBrowsers() }
                    .disabled(state.isBrowserScanInProgress)

                if needsDiaAutomationAccess {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Dia profile control", systemImage: "cursorarrow.click.2")
                            .font(.headline)
                        Text("Reflex uses macOS Automation to focus the selected Dia profile before it opens a link. It does not read tabs or page content.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button(diaAutomationButtonTitle) { requestDiaAutomationAccess() }
                                .disabled(isRequestingDiaAccess || diaAutomationState == .authorized)
                            if isRequestingDiaAccess {
                                ProgressView().controlSize(.small)
                            }
                            if diaAutomationState == .authorized {
                                Label("Allowed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if diaAutomationState == .denied {
                                Text("Access is off. Change it in System Settings > Privacy & Security > Automation.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private var automaticRoutingStep: some View {
        OnboardingPage(
            eyebrow: "OPTIONAL",
            title: "Enable automatic routing with Jev.",
            detail: "Add an OpenRouter API key to let Jev select a target when it is confident. Without a key, Reflex always shows the chooser."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if state.hasAPIKey {
                    statusCard(
                        isComplete: true,
                        completeText: "Your API key is saved in Keychain",
                        incompleteText: "No API key is configured"
                    )
                    Toggle("Use Jev for automatic routing", isOn: $state.usesJev)
                        .toggleStyle(.checkbox)
                } else {
                    SecureField("OpenRouter API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($isAPIKeyFocused)
                        .textContentType(.password)
                        .accessibilityLabel("OpenRouter API key")
                    HStack(spacing: 10) {
                        Button("Save API Key") { saveAPIKey() }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Stored in macOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let apiKeyMessage {
                    Text(apiKeyMessage)
                        .font(.caption)
                        .foregroundStyle(state.hasAPIKey ? Color.secondary : Color.red)
                }
                Text("For each decision, Reflex sends the link scheme, host, path, query parameter names, source app, and enabled target names and purposes. It does not send query values or fragments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var browsersStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("BROWSERS AND PROFILES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text("Tell Reflex where each link belongs.")
                    .font(.system(size: 27, weight: .bold))
                Text("Select a suggestion or write your own purpose. These words help Jev choose. Leave a purpose empty if you prefer the chooser.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(state.targets.count) target\(state.targets.count == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if state.isBrowserScanInProgress {
                    ProgressView().controlSize(.small)
                }
                Button("Rescan") { state.rescanBrowsers() }
                    .disabled(state.isBrowserScanInProgress)
            }

            if state.targets.isEmpty, !state.isBrowserScanInProgress {
                ContentUnavailableView(
                    "No Supported Browser Found",
                    systemImage: "globe.badge.chevron.backward",
                    description: Text("Install or open a supported browser, then select Rescan.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.targets) { target in
                            browserPurposeCard(target)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 44)
        .padding(.bottom, 20)
    }

    private var readyStep: some View {
        OnboardingPage(
            eyebrow: "SETUP COMPLETE",
            title: "Reflex is ready.",
            detail: "You can change every choice later in Settings. Reflex stays in the menu bar after this window closes."
        ) {
            VStack(spacing: 12) {
                summaryRow(
                    symbol: state.defaultBrowserStatus.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle",
                    color: state.defaultBrowserStatus.isComplete ? .green : .orange,
                    title: "Default browser",
                    value: state.defaultBrowserStatus.isComplete ? "Ready" : "Finish later in Settings"
                )
                summaryRow(
                    symbol: state.hasAPIKey && state.usesJev ? "sparkles" : "hand.tap",
                    color: .accentColor,
                    title: "Link selection",
                    value: state.hasAPIKey && state.usesJev ? "Automatic routing and chooser" : "Chooser"
                )
                summaryRow(
                    symbol: "globe",
                    color: .accentColor,
                    title: "Enabled targets",
                    value: "\(state.targets.filter(\.isEnabled).count)"
                )
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Spacer()
            if step == .automaticRouting, !state.hasAPIKey {
                Text("You can skip this step")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(primaryButtonTitle) {
                if step == .ready {
                    onFinish()
                } else {
                    move(by: 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    private func browserPurposeCard(_ target: BrowserTarget) -> some View {
        let binding = Binding(
            get: { state.targets.first(where: { $0.id == target.id }) ?? target },
            set: { updated in
                guard let index = state.targets.firstIndex(where: { $0.id == target.id }) else { return }
                state.targets[index] = updated
            }
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let icon = state.icon(for: target) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name).font(.headline)
                    if state.targets.filter({ $0.bundleIdentifier == target.bundleIdentifier }).count > 1 {
                        Text("Browser profile").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Enabled", isOn: binding.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Enable \(target.name)")
            }
            TextField("What do you use this target for?", text: binding.purpose)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Purpose for \(target.name)")
            HStack(spacing: 6) {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(OnboardingPurposeSuggestion.ordered(for: target.name).prefix(4)) { suggestion in
                    Button {
                        binding.wrappedValue.purpose = suggestion.purpose
                    } label: {
                        Label(suggestion.title, systemImage: suggestion.symbol)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(suggestion.purpose)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusCard(isComplete: Bool, completeText: String, incompleteText: String) -> some View {
        Label(
            isComplete ? completeText : incompleteText,
            systemImage: isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .font(.headline)
        .foregroundStyle(isComplete ? Color.green : Color.orange)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summaryRow(symbol: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func saveAPIKey() {
        do {
            try state.saveAPIKey(apiKey)
            state.usesJev = true
            apiKey = ""
            isAPIKeyFocused = false
            apiKeyMessage = "The API key is saved in Keychain."
        } catch {
            apiKeyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func move(by amount: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + amount) else { return }
        if step == .automaticRouting, amount > 0, !state.hasAPIKey {
            state.usesJev = false
        }
        step = next
        if next == .profileAccess || next == .browsers {
            state.rescanBrowsers()
        }
    }

    private var primaryButtonTitle: String {
        if step == .ready { return "Start Using Reflex" }
        if step == .automaticRouting, !state.hasAPIKey { return "Skip for Now" }
        return "Continue"
    }

    private var needsDiaAutomationAccess: Bool {
        let diaTargets = state.targets.filter {
            $0.bundleIdentifier == AutomationPermissionService.diaBundleIdentifier
                && $0.chromiumProfileDirectory != nil
        }
        return diaTargets.count > 1
    }

    private var diaAutomationButtonTitle: String {
        switch diaAutomationState {
        case .authorized: "Dia Control Allowed"
        case .denied: "Check Dia Access"
        case .notDetermined, .unavailable: "Allow Dia Control"
        }
    }

    private func requestDiaAutomationAccess() {
        isRequestingDiaAccess = true
        Task {
            diaAutomationState = await AutomationPermissionService.requestDiaAccess()
            isRequestingDiaAccess = false
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.system(size: 29, weight: .bold))
                .padding(.top, 7)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
            content
                .padding(.top, 28)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 42)
        .padding(.top, 66)
        .padding(.bottom, 28)
    }
}

private struct OnboardingFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
