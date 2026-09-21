import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case targets = "Targets"
    case routing = "AI Routing"

    var id: String { rawValue }

    var identifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .targets: return "globe"
        case .routing: return "sparkles"
        }
    }
}

@MainActor
final class SettingsNavigationState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var navigation: SettingsNavigationState = SettingsNavigationState()
    @FocusState private var isFieldFocused: Bool
    @State private var apiKey = ""
    @State private var isShowingSavedPlaceholder = false
    @State private var keyMessage: String?
    @State private var draggingTargetID: UUID?

    private let savedKeyMask = "••••••••••••••••"

    private var isKeySaveable: Bool {
        !isShowingSavedPlaceholder &&
        apiKey != savedKeyMask &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            switch navigation.selectedTab {
            case .general:
                generalTab
            case .targets:
                targetsTab
            case .routing:
                routingTab
            }
        }
        .frame(minWidth: 580, idealWidth: 620, maxWidth: 650, minHeight: 450, idealHeight: 500)
    }

    private var generalTab: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 20) {
                    GridRow {
                        Text("Default web browser:")
                            .font(.system(size: 13))
                            .gridColumnAlignment(.trailing)
                            .frame(width: 155, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                Label(
                                    state.defaultBrowserStatus.ownsHTTP ? "HTTP: Reflex" : "HTTP: Other browser",
                                    systemImage: state.defaultBrowserStatus.ownsHTTP ? "checkmark.circle.fill" : "exclamationmark.circle"
                                )
                                .foregroundStyle(state.defaultBrowserStatus.ownsHTTP ? Color.green : Color.orange)
                                .font(.system(size: 13))

                                Label(
                                    state.defaultBrowserStatus.ownsHTTPS ? "HTTPS: Reflex" : "HTTPS: Other browser",
                                    systemImage: state.defaultBrowserStatus.ownsHTTPS ? "checkmark.circle.fill" : "exclamationmark.circle"
                                )
                                .foregroundStyle(state.defaultBrowserStatus.ownsHTTPS ? Color.green : Color.orange)
                                .font(.system(size: 13))
                            }
                            Button("Make Reflex Default Browser") {
                                state.makeDefaultBrowser()
                            }
                            .disabled(state.defaultBrowserStatus.isComplete)

                            if let message = state.setupMessage {
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Text("Links from other applications normally reach Reflex only when it is the default browser. Links inside a browser or an embedded web view can bypass Reflex.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GridRow {
                        Text("Menu bar:")
                            .font(.system(size: 13))
                            .gridColumnAlignment(.trailing)
                            .frame(width: 155, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Show Reflex in the menu bar", isOn: $state.showsMenuBarItem)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 13))

                            Text("When on, closing this window removes the Dock icon and keeps Reflex in the menu bar. When off, closing this window quits Reflex.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GridRow {
                        Text("Chooser shortcut:")
                            .font(.system(size: 13))
                            .gridColumnAlignment(.trailing)
                            .frame(width: 155, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $state.chooserModifier) {
                                ForEach(ChooserModifier.allCases) { modifier in
                                    Label(
                                        "\(modifier.name) + click",
                                        systemImage: modifier.symbolName
                                    )
                                    .tag(modifier)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180, alignment: .leading)

                            Text("Hold \(state.chooserModifier.name) while you click a link to skip automatic selection and show the chooser. The chooser also gives access to Settings. The source application can use some modified clicks itself, so the link might not reach Reflex.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GridRow {
                        Text("Profile access:")
                            .font(.system(size: 13))
                            .gridColumnAlignment(.trailing)
                            .frame(width: 155, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 8) {
                            if state.profileAccessDeniedBrowsers.isEmpty,
                               state.missingProfileDataBrowsers.isEmpty {
                                Label(
                                    "No profile access problem was found.",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            }
                            if !state.profileAccessDeniedBrowsers.isEmpty {
                                Label(
                                    "macOS blocks the profiles of \(state.profileAccessDeniedBrowsers.joined(separator: ", ")).",
                                    systemImage: "lock.circle"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                                Button("Open Full Disk Access") { state.openFullDiskAccessSettings() }
                                Text("Add Reflex to the list and switch it on. Then start Reflex again and select Rescan Browsers. Reflex works without this access, but it shows one target for each of these browsers.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !state.missingProfileDataBrowsers.isEmpty {
                                Label(
                                    "No profile data was found for \(state.missingProfileDataBrowsers.joined(separator: ", ")).",
                                    systemImage: "questionmark.circle"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                Text("Start each browser once, then select Rescan Browsers. Invalid profile data also appears in this state.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("Reflex reads profile directories and profile names. When Edge stores a placeholder profile name, Reflex can read account-name fields from that profile record. The value can become a target name and can be sent to OpenRouter when automatic selection is active. Reflex reads no history, cookies, or page data.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
    }

    private var targetsTab: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Configured targets:")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if state.targets.count > 1 {
                        Text("Drag to reorder chooser shortcuts")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if state.targets.isEmpty {
                    Text("No registered web browser was found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let shortcutNumbers = shortcutNumbers()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(browserGroups(), id: \.first) { targetIDs in
                            VStack(alignment: .leading, spacing: 6) {
                                browserHeader(for: targetIDs)
                                ForEach(targetIDs, id: \.self) { targetID in
                                    targetRow(targetID: targetID, shortcutNumbers: shortcutNumbers)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Add Browser…") { addBrowser() }
                    Button("Rescan Browsers") { state.rescanBrowsers() }
                    Spacer()
                }
                .padding(.top, 4)

                Text("The purpose is what Jev reads. Write the accounts, sites, and work you use a target for, for example \"Work: GitHub, Linear, company mail\". A target with no purpose is hard for Jev to choose, so Reflex shows the chooser instead.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A browser with more than one profile becomes one target for each profile. A browser with a single profile stays one target.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
        }
    }

    private var routingTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 18) {
                GridRow {
                    Text("API key:")
                        .font(.system(size: 13))
                        .gridColumnAlignment(.trailing)
                        .frame(width: 155, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("OpenRouter API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .focused($isFieldFocused)
                            .textContentType(.password)
                            .accessibilityLabel("OpenRouter API key")
                            .accessibilityValue(isShowingSavedPlaceholder ? "Saved in Keychain" : (apiKey.isEmpty ? "Not configured" : "Entered API key"))
                            .onChange(of: isFieldFocused) { _, isFocused in
                                if isFocused {
                                    if isShowingSavedPlaceholder || apiKey == savedKeyMask {
                                        apiKey = ""
                                        isShowingSavedPlaceholder = false
                                    }
                                } else {
                                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.hasAPIKey {
                                        apiKey = savedKeyMask
                                        isShowingSavedPlaceholder = true
                                    }
                                }
                            }
                            .onAppear {
                                if state.hasAPIKey && apiKey.isEmpty {
                                    apiKey = savedKeyMask
                                    isShowingSavedPlaceholder = true
                                }
                            }
                            .onChange(of: state.hasAPIKey) { _, hasKey in
                                if !hasKey {
                                    apiKey = ""
                                    isShowingSavedPlaceholder = false
                                } else if !isFieldFocused && (apiKey.isEmpty || isShowingSavedPlaceholder) {
                                    apiKey = savedKeyMask
                                    isShowingSavedPlaceholder = true
                                }
                            }

                        HStack(spacing: 8) {
                            Button("Save") {
                                do {
                                    try state.saveAPIKey(apiKey)
                                    isFieldFocused = false
                                    apiKey = savedKeyMask
                                    isShowingSavedPlaceholder = true
                                    keyMessage = "The API key is saved in Keychain."
                                } catch {
                                    keyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                }
                            }
                            .disabled(!isKeySaveable)

                            Button("Remove") {
                                do {
                                    try state.removeAPIKey()
                                    isFieldFocused = false
                                    apiKey = ""
                                    isShowingSavedPlaceholder = false
                                    keyMessage = "The API key was removed."
                                } catch {
                                    keyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                }
                            }
                            .disabled(!state.hasAPIKey)

                            Text(state.hasAPIKey ? "Saved in Keychain" : "Not configured")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if let keyMessage {
                            Text(keyMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text("Reflex stores your OpenRouter API key securely in the macOS Keychain.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    Text("Automatic selection:")
                        .font(.system(size: 13))
                        .gridColumnAlignment(.trailing)
                        .frame(width: 155, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Use Jev for automatic selection", isOn: $state.usesJev)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 13))
                            .disabled(!state.hasAPIKey)

                        Text("Reflex sends a privacy-reduced description of the link and enabled targets to TypeSafe Jev to automatically choose the best target.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if state.usesJev {
                    GridRow {
                        Text("Auto-route confidence:")
                            .font(.system(size: 13))
                            .gridColumnAlignment(.trailing)
                            .frame(width: 155, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Slider(
                                    value: $state.autoRouteConfidenceThreshold,
                                    in: 0.50...1.0,
                                    step: 0.05
                                ) {
                                    Text("Auto-route confidence")
                                }
                                .labelsHidden()
                                .frame(width: 180)

                                Text("\(Int(round(state.autoRouteConfidenceThreshold * 100)))%")
                                    .monospacedDigit()
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .disabled(!state.hasAPIKey)

                            Text("Reflex opens links automatically only when Jev's confidence is at or above this threshold. Lower confidence shows the chooser with the suggested target highlighted.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                GridRow {
                    Text("Privacy boundary:")
                        .font(.system(size: 13))
                        .gridColumnAlignment(.trailing)
                        .frame(width: 155, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reflex sends the link scheme, host, path, query parameter names, source application identifier when available, and enabled target names and purposes. It never sends query values, fragments, clipboard contents, or browser history.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    /// Targets of one browser sit next to each other, so a run of them is one group.
    private func browserGroups() -> [[UUID]] {
        var groups: [[UUID]] = []
        for target in state.targets {
            if let lastID = groups.last?.last,
               state.targets.first(where: { $0.id == lastID })?.bundleIdentifier == target.bundleIdentifier {
                groups[groups.count - 1].append(target.id)
            } else {
                groups.append([target.id])
            }
        }
        return groups
    }

    @ViewBuilder
    private func browserHeader(for targetIDs: [UUID]) -> some View {
        if let targetID = targetIDs.first,
           let target = state.targets.first(where: { $0.id == targetID }) {
            HStack(spacing: 8) {
                if let icon = state.icon(for: target) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(BrowserTarget.baseName(of: target.name))
                    .font(.system(size: 13, weight: .semibold))
                Text(target.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func targetRow(targetID: UUID, shortcutNumbers: [UUID: Int]) -> some View {
        if let target = state.targets.first(where: { $0.id == targetID }) {
            let targetBinding = Binding(
                get: { state.targets.first(where: { $0.id == targetID }) ?? target },
                set: { updatedTarget in
                    guard let index = state.targets.firstIndex(where: { $0.id == targetID }) else { return }
                    state.targets[index] = updatedTarget
                }
            )
            let isMultiProfile = state.targets.filter { $0.bundleIdentifier == target.bundleIdentifier }.count > 1
            let placeholder = isMultiProfile ? "What do you use this profile for" : "What do you use this browser for"
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    DragHandle(target: target, draggingTargetID: $draggingTargetID)
                    Toggle("Enabled", isOn: targetBinding.isEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    TextField("Name", text: targetBinding.name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Target name")
                    if !state.isAvailable(target) {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                    keyBadge(shortcutNumbers[target.id])
                    Button(role: .destructive) {
                        state.removeTarget(id: target.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(target.name)")
                }
                HStack(spacing: 6) {
                    Text("Purpose:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                    TextField(placeholder, text: targetBinding.purpose)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(placeholder)
                }
            }
            .padding(.leading, 12)
            .opacity(draggingTargetID == target.id ? 0.4 : 1)
            .onDrop(
                of: [.text],
                delegate: TargetDropDelegate(
                    target: target,
                    targets: $state.targets,
                    draggingTargetID: $draggingTargetID
                )
            )
        }
    }

    /// An empty badge keeps the trash button in the same column on every row.
    @ViewBuilder
    private func keyBadge(_ number: Int?) -> some View {
        if let number {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 22, height: 22)
                .background(
                    Color.primary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .accessibilityLabel("Key \(number)")
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    /// The chooser numbers the targets it can show, so a disabled or missing browser has no key.
    private func shortcutNumbers() -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for (index, target) in state.availableTargets.prefix(9).enumerated() {
            numbers[target.id] = index + 1
        }
        return numbers
    }

    private func addBrowser() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a browser application."
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
        state.addTarget(applicationURL: applicationURL)
    }
}

private struct DragHandle: View {
    let target: BrowserTarget
    @Binding var draggingTargetID: UUID?
    @State private var showsOpenHand = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder \(target.name)")
            .onDrag {
                draggingTargetID = target.id
                NSCursor.closedHand.set()
                return NSItemProvider(object: target.id.uuidString as NSString)
            }
            .onHover { isHovering in
                if isHovering, !showsOpenHand {
                    NSCursor.openHand.push()
                    showsOpenHand = true
                } else if !isHovering, showsOpenHand {
                    NSCursor.pop()
                    showsOpenHand = false
                }
            }
            .onDisappear {
                if showsOpenHand {
                    NSCursor.pop()
                    showsOpenHand = false
                }
            }
    }
}

private struct TargetDropDelegate: DropDelegate {
    let target: BrowserTarget
    @Binding var targets: [BrowserTarget]
    @Binding var draggingTargetID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggingTargetID == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggingTargetID else { return false }
        // Apply the move on drop. A live row move can put the pointer over a different
        // row and immediately reverse a full browser-group move.
        withAnimation {
            targets = targets.movingTarget(draggedID, over: target.id)
        }
        draggingTargetID = nil
        return true
    }
}
