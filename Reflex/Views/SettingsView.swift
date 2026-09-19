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
                            keyMessage = "Reflex could not save the API key."
                        }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove") {
                        do {
                            try state.removeAPIKey()
                            apiKey = ""
                            keyMessage = "The API key was removed."
                        } catch {
                            keyMessage = "Reflex could not remove the API key."
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
                if let message = state.setupMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("Links from other applications normally reach Reflex only when it is the default browser. Links inside a browser or an embedded web view can bypass Reflex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser targets") {
                if state.targets.isEmpty {
                    Text("No registered web browser was found.")
                }
                if state.targets.count > 1 {
                    Text("Drag a row by its handle to set the chooser order. The number is the key that opens that target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($state.targets) { $target in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            dragHandle(for: target)
                            Toggle("Enabled", isOn: $target.isEnabled).labelsHidden()
                            if let icon = BrowserLauncher().icon(for: target) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            TextField("Name", text: $target.name)
                                .labelsHidden()
                                .accessibilityLabel("Target name")
                            if !BrowserLauncher().isAvailable(target) {
                                Text("Unavailable").foregroundStyle(.secondary)
                            }
                            if let number = shortcutNumber(for: target) {
                                Text("\(number)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .frame(width: 20, height: 20)
                                    .background(
                                        Color.primary.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    )
                                    .accessibilityLabel("Key \(number)")
                            }
                            Button(role: .destructive) {
                                state.removeTarget(id: target.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(target.name)")
                        }
                        Text(target.bundleIdentifier)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("Purpose", text: $target.purpose)
                        TextField(
                            "Chromium profile directory (optional)",
                            text: Binding(
                                get: { target.chromiumProfileDirectory ?? "" },
                                set: { target.chromiumProfileDirectory = $0.isEmpty ? nil : $0 }
                            )
                        )
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
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
                HStack {
                    Button("Add Browser…") { addBrowser() }
                    Button("Rescan Browsers") { state.rescanBrowsers() }
                    Button("Rescan Profiles") { state.discoverProfiles() }
                }
                if !state.discoveredProfiles.isEmpty {
                    Divider()
                    Text("Discovered profiles")
                        .font(.headline)
                    ForEach(state.discoveredProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(profile.browserName) — \(profile.profileName)")
                                Text(profile.profileDirectory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { state.addDiscoveredProfile(profile) }
                                .accessibilityLabel("Add \(profile.browserName) profile \(profile.profileName)")
                        }
                    }
                }
                if let message = state.profileDiscoveryMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { state.discoverProfiles() }
    }

    private func dragHandle(for target: BrowserTarget) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 20)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder \(target.name)")
            .onDrag {
                draggingTargetID = target.id
                return NSItemProvider(object: target.id.uuidString as NSString)
            }
    }

    /// The chooser numbers the targets it can show, so a disabled or missing browser has no key.
    private func shortcutNumber(for target: BrowserTarget) -> Int? {
        guard let index = state.availableTargets.firstIndex(where: { $0.id == target.id }),
              index < 9 else {
            return nil
        }
        return index + 1
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
