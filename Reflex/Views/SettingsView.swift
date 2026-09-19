import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var apiKey = ""
    @State private var keyMessage: String?
    @State private var draggingTargetID: UUID?

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
                    .accessibilityLabel("OpenRouter API key")
                HStack {
                    Button("Save") {
                        do {
                            try state.saveAPIKey(apiKey)
                            apiKey = ""
                            keyMessage = "The API key is saved in Keychain."
                        } catch {
                            keyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove") {
                        do {
                            try state.removeAPIKey()
                            apiKey = ""
                            keyMessage = "The API key was removed."
                        } catch {
                            keyMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                    .disabled(!state.hasAPIKey)
                    Spacer()
                    Text(state.hasAPIKey ? "Saved in Keychain" : "Not configured")
                        .foregroundStyle(.secondary)
                }
                if let keyMessage {
                    Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Reflex sends the link scheme, host, path, query parameter names, source application identifier when available, and enabled target names and purposes. It never sends query values or fragments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default browser") {
                HStack {
                    Label(
                        state.defaultBrowserStatus.ownsHTTP ? "HTTP: Reflex" : "HTTP: Other browser",
                        systemImage: state.defaultBrowserStatus.ownsHTTP ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    Spacer()
                    Label(
                        state.defaultBrowserStatus.ownsHTTPS ? "HTTPS: Reflex" : "HTTPS: Other browser",
                        systemImage: state.defaultBrowserStatus.ownsHTTPS ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                }
                Button("Make Reflex Default Browser") { state.makeDefaultBrowser() }
                    .disabled(state.defaultBrowserStatus.isComplete)
                if let message = state.setupMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("Links from other applications normally reach Reflex only when it is the default browser. Links inside a browser or an embedded web view can bypass Reflex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle("Show Reflex in the menu bar", isOn: $state.showsMenuBarItem)
                Text("When the menu bar item is on, closing this window removes the Dock icon and keeps Reflex in the menu bar. When it is off, closing this window quits Reflex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Chooser shortcut") {
                Picker("Modifier key", selection: $state.chooserModifier) {
                    ForEach(ChooserModifier.allCases) { modifier in
                        Label(
                            "\(modifier.name) + click",
                            systemImage: modifier.symbolName
                        )
                        .tag(modifier)
                    }
                }
                Text("Hold \(state.chooserModifier.name) while you click a link to skip automatic selection and show the chooser. The chooser also gives access to Settings. The source application can use some modified clicks itself, so the link might not reach Reflex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profile access") {
                if state.profileAccessDeniedBrowsers.isEmpty,
                   state.missingProfileDataBrowsers.isEmpty {
                    Label(
                        "No profile access problem was found.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }
                if !state.profileAccessDeniedBrowsers.isEmpty {
                    Label(
                        "macOS blocks the profiles of \(state.profileAccessDeniedBrowsers.joined(separator: ", ")).",
                        systemImage: "lock.circle"
                    )
                    Button("Open Full Disk Access") { state.openFullDiskAccessSettings() }
                    Text("Add Reflex to the list and switch it on. Then start Reflex again and select Rescan Browsers. Reflex works without this access, but it shows one target for each of these browsers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !state.missingProfileDataBrowsers.isEmpty {
                    Label(
                        "No profile data was found for \(state.missingProfileDataBrowsers.joined(separator: ", ")).",
                        systemImage: "questionmark.circle"
                    )
                    Text("Start each browser once, then select Rescan Browsers. Invalid profile data also appears in this state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Reflex reads profile directories and profile names. When Edge stores a placeholder profile name, Reflex can read account-name fields from that profile record. The value can become a target name and can be sent to OpenRouter when automatic selection is active. Reflex reads no history, cookies, or page data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser targets") {
                if state.targets.isEmpty {
                    Text("No registered web browser was found.")
                }
                Text("The purpose is what Jev reads. Write the accounts, sites, and work you use a target for, for example \"Slumber work: GitHub, Linear, company mail\". A target with no purpose is hard for Jev to choose, so Reflex shows the chooser instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state.targets.count > 1 {
                    Text("Drag a row by its handle to set the chooser order. The number is the key that opens that target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let shortcutNumbers = shortcutNumbers()
                ForEach(browserGroups(), id: \.first) { indices in
                    VStack(alignment: .leading, spacing: 8) {
                        browserHeader(for: indices)
                        ForEach(indices, id: \.self) { index in
                            targetRow(index: index, shortcutNumbers: shortcutNumbers)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    Button("Add Browser…") { addBrowser() }
                    Button("Rescan Browsers") { state.rescanBrowsers() }
                }
                Text("A browser with more than one profile becomes one target for each profile. A browser with a single profile stays one target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Targets of one browser sit next to each other, so a run of them is one group.
    private func browserGroups() -> [[Int]] {
        var groups: [[Int]] = []
        for index in state.targets.indices {
            if let lastIndex = groups.last?.last,
               state.targets[lastIndex].bundleIdentifier == state.targets[index].bundleIdentifier {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
    }

    @ViewBuilder
    private func browserHeader(for indices: [Int]) -> some View {
        let target = state.targets[indices[0]]
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

    private func targetRow(index: Int, shortcutNumbers: [UUID: Int]) -> some View {
        let target = state.targets[index]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                DragHandle(target: target, draggingTargetID: $draggingTargetID)
                Toggle("Enabled", isOn: $state.targets[index].isEnabled).labelsHidden()
                TextField("Name", text: $state.targets[index].name)
                    .labelsHidden()
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
            TextField("Purpose: what you use this target for", text: $state.targets[index].purpose)
                .accessibilityLabel("Purpose")
            TextField(
                "Chromium profile directory (optional)",
                text: Binding(
                    get: { state.targets[index].chromiumProfileDirectory ?? "" },
                    set: { state.targets[index].chromiumProfileDirectory = $0.isEmpty ? nil : $0 }
                )
            )
            .font(.caption)
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

    func dropEntered(info: DropInfo) {
        guard let draggingTargetID,
              draggingTargetID != target.id,
              let from = targets.firstIndex(where: { $0.id == draggingTargetID }),
              let to = targets.firstIndex(where: { $0.id == target.id }) else {
            return
        }
        withAnimation {
            targets.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: draggingTargetID == nil ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let wasDragging = draggingTargetID != nil
        draggingTargetID = nil
        return wasDragging
    }
}
