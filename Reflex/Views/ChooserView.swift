import SwiftUI

struct ChooserView: View {
    @ObservedObject var state: AppState
    @State private var selectedTargetID: UUID?

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
                    ScrollView {
                        LazyVStack(spacing: 8) {
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
                                        Text(index < 9 ? "\(index + 1)" : "")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .reflexNumberShortcut(index)
                                .tint(selectedTargetID == target.id ? .accentColor : nil)
                                .accessibilityLabel("Open in \(target.name)")
                                .accessibilityAddTraits(selectedTargetID == target.id ? .isSelected : [])
                            }
                        }
                    }
                    .frame(maxHeight: 260)
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
        .focusable()
        .focusEffectDisabled()
        .onAppear { selectSuggestedOrFirstTarget() }
        .onChange(of: state.suggestedTargetID) { _, _ in selectSuggestedOrFirstTarget() }
        .onChange(of: state.availableTargets.map(\.id)) { _, _ in selectSuggestedOrFirstTarget() }
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.return) {
            guard let target = state.availableTargets.first(where: { $0.id == selectedTargetID }) else {
                return .ignored
            }
            state.openPending(in: target)
            return .handled
        }
    }

    private func selectSuggestedOrFirstTarget() {
        let targetIDs = state.availableTargets.map(\.id)
        if let suggestion = state.suggestedTargetID, targetIDs.contains(suggestion) {
            selectedTargetID = suggestion
        } else if selectedTargetID == nil || !targetIDs.contains(selectedTargetID!) {
            selectedTargetID = targetIDs.first
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let targetIDs = state.availableTargets.map(\.id)
        guard !targetIDs.isEmpty else { return }
        let currentIndex = selectedTargetID.flatMap { targetIDs.firstIndex(of: $0) } ?? 0
        let nextIndex: Int
        switch direction {
        case .down, .right:
            nextIndex = min(currentIndex + 1, targetIDs.count - 1)
        case .up, .left:
            nextIndex = max(currentIndex - 1, 0)
        @unknown default:
            nextIndex = currentIndex
        }
        selectedTargetID = targetIDs[nextIndex]
    }
}

private extension View {
    @ViewBuilder
    func reflexNumberShortcut(_ index: Int) -> some View {
        if index < 9 {
            keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        } else {
            self
        }
    }
}
