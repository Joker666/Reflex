import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 20) {
                    GridRow {
                        SettingsText.gridLabel("Default web browser:")

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
                                SettingsText.footnote(message)
                            }

                            SettingsText.footnote("Links from other applications normally reach Reflex only when it is the default browser. Links inside a browser or an embedded web view can bypass Reflex.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GridRow {
                        SettingsText.gridLabel("Menu bar:")

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Show Reflex in the menu bar", isOn: $state.showsMenuBarItem)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 13))

                            SettingsText.footnote("When on, closing this window removes the Dock icon and keeps Reflex in the menu bar. When off, closing this window quits Reflex.")
                        }
                    }

                    GridRow {
                        SettingsText.gridLabel("Chooser shortcut:")

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

                            SettingsText.footnote("Hold \(state.chooserModifier.name) while you click a link to skip automatic selection and show the chooser. The chooser also gives access to Settings. The source application can use some modified clicks itself, so the link might not reach Reflex.")
                        }
                    }

                    GridRow {
                        SettingsText.gridLabel("Profile access:")

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
                                SettingsText.footnote("Add Reflex to the list and switch it on. Then start Reflex again and select Rescan Browsers. Reflex works without this access, but it shows one target for each of these browsers.")
                            }
                            if !state.missingProfileDataBrowsers.isEmpty {
                                Label(
                                    "No profile data was found for \(state.missingProfileDataBrowsers.joined(separator: ", ")).",
                                    systemImage: "questionmark.circle"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                SettingsText.footnote("Start each browser once, then select Rescan Browsers. Invalid profile data also appears in this state.")
                            }
                            SettingsText.footnote("Reflex reads profile directories and profile names. When Edge stores a placeholder profile name, Reflex can read account-name fields from that profile record. The value can become a target name and can be sent to OpenRouter when automatic selection is active. Reflex reads no history, cookies, or page data.")
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
}
