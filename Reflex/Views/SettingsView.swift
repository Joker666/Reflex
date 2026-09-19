import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var apiKey = ""
    @State private var keyMessage: String?

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
                ForEach($state.targets) { $target in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle("Enabled", isOn: $target.isEnabled).labelsHidden()
                            if let icon = BrowserLauncher().icon(for: target) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            TextField("Name", text: $target.name)
                            if !BrowserLauncher().isAvailable(target) {
                                Text("Unavailable").foregroundStyle(.secondary)
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
