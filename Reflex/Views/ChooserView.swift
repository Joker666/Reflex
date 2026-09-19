import SwiftUI

struct ChooserView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let url = state.pendingURL {
                Text("Open \(url.host ?? "link") in")
                    .font(.headline)

                if state.isRouting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Selecting a browser…")
                    }
                    .font(.caption)
                } else if state.isJevUnavailable {
                    Label("Automatic selection is unavailable", systemImage: "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if state.availableTargets.isEmpty {
                    ContentUnavailableView(
                        "No Browser Is Available",
                        systemImage: "safari",
                        description: Text("Enable an installed browser in Settings. The link stays in Reflex.")
                    )
                    SettingsLink { Text("Open Settings") }
                } else {
                    ForEach(Array(state.availableTargets.enumerated()), id: \.element.id) { index, target in
                        Button {
                            state.openPending(in: target)
                        } label: {
                            HStack {
                                Text(target.name)
                                if state.suggestedTargetID == target.id {
                                    Text("Suggested")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(index < 9 ? "⌘\(index + 1)" : "")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(index < 9 ? KeyEquivalent(Character(String(index + 1))) : .init("0"), modifiers: .command)
                        .accessibilityLabel("Open in \(target.name)")
                    }
                }

                if let error = state.launchError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Cancel") { state.cancelPending() }
                    .keyboardShortcut(.cancelAction)
            } else {
                ContentUnavailableView(
                    "Reflex Is Ready",
                    systemImage: "arrow.triangle.branch",
                    description: Text("External web links will appear here after Reflex is the default browser.")
                )
                if !state.defaultBrowserStatus.isComplete {
                    Button("Make Reflex Default Browser") { state.makeDefaultBrowser() }
                }
                SettingsLink { Text("Open Settings") }
            }
        }
        .padding(20)
    }
}
