import SwiftUI

struct RoutingSettingsTab: View {
    @ObservedObject var state: AppState
    @FocusState private var isFieldFocused: Bool
    @State private var apiKey = ""
    @State private var isShowingSavedPlaceholder = false
    @State private var keyMessage: String?

    private let savedKeyMask = "••••••••••••••••"

    private var isKeySaveable: Bool {
        !isShowingSavedPlaceholder &&
        apiKey != savedKeyMask &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 18) {
                GridRow {
                    SettingsText.gridLabel("API key:")

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
                                    keyMessage = error.localizedDescription
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
                                    keyMessage = error.localizedDescription
                                }
                            }
                            .disabled(!state.hasAPIKey)

                            Text(state.hasAPIKey ? "Saved in Keychain" : "Not configured")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if let keyMessage {
                            SettingsText.footnote(keyMessage)
                        }

                        SettingsText.footnote("Reflex stores your OpenRouter API key securely in the macOS Keychain.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    SettingsText.gridLabel("Automatic selection:")

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Use Jev for automatic selection", isOn: $state.usesJev)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 13))
                            .disabled(!state.hasAPIKey)

                        SettingsText.footnote("Reflex sends a privacy-reduced description of the link and enabled targets to TypeSafe Jev to automatically choose the best target.")
                    }
                }

                if state.usesJev {
                    GridRow {
                        SettingsText.gridLabel("Auto-route confidence:")

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

                                Text(SettingsText.percent(state.autoRouteConfidenceThreshold))
                                    .monospacedDigit()
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .disabled(!state.hasAPIKey)

                            SettingsText.footnote("Reflex opens links automatically only when Jev's confidence is at or above this threshold. Lower confidence shows the chooser with the suggested target highlighted.")
                        }
                    }
                }

                GridRow {
                    SettingsText.gridLabel("Privacy boundary:")

                    VStack(alignment: .leading, spacing: 6) {
                        SettingsText.footnote(JevClient.privacyNote)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
}
