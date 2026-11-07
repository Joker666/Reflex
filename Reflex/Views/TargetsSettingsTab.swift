import SwiftUI

struct TargetsSettingsTab: View {
    @ObservedObject var state: AppState
    @State private var draggedTargetID: UUID?
    @State private var dropSlot: DropSlot?

    var body: some View {
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
                    let groups = browserGroups()
                    // Padding replaces stack spacing, so every point of the list accepts a drop.
                    VStack(alignment: .leading, spacing: 0) {
                        // The bundle identifier keeps a group's identity when its first target moves.
                        ForEach(groups, id: \.first?.bundleIdentifier) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                browserHeader(for: group[0])
                                    .padding(.bottom, 3)
                                ForEach(group) { target in
                                    targetRow(
                                        target: target,
                                        isProfileTarget: group.count > 1,
                                        shortcutNumbers: shortcutNumbers
                                    )
                                }
                            }
                            .padding(.top, group[0].id == groups.first?.first?.id ? 0 : 9)
                            .contentShape(Rectangle())
                            // A drop on the header or the space above it goes over the first target.
                            .onDrop(
                                of: [.reflexTarget],
                                delegate: dropDelegate(DropSlot(area: .header, targetID: group[0].id))
                            )
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Add Browser…") { addBrowser() }
                    Button("Rescan Browsers") { state.rescanBrowsers() }
                    Spacer()
                }
                .padding(.top, 4)

                SettingsText.footnote("The purpose is what Jev reads. Write the accounts, sites, and work you use a target for, for example \"Work: GitHub, Linear, company mail\". A target with no purpose is hard for Jev to choose, so Reflex shows the chooser instead.")

                SettingsText.footnote("A browser with more than one profile becomes one target for each profile. A browser with a single profile stays one target.")
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    /// Targets of one browser sit next to each other, so a run of them is one group.
    private func browserGroups() -> [[BrowserTarget]] {
        var groups: [[BrowserTarget]] = []
        for target in state.targets {
            if groups.last?.last?.bundleIdentifier == target.bundleIdentifier {
                groups[groups.count - 1].append(target)
            } else {
                groups.append([target])
            }
        }
        return groups
    }

    private func browserHeader(for target: BrowserTarget) -> some View {
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

    private func targetRow(
        target: BrowserTarget,
        isProfileTarget: Bool,
        shortcutNumbers: [UUID: Int]
    ) -> some View {
        let targetBinding = state.binding(for: target)
        let placeholder = isProfileTarget
            ? "What do you use this profile for"
            : "What do you use this browser for"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DragHandle(
                    target: target,
                    icon: state.icon(for: target),
                    draggedTargetID: $draggedTargetID
                )
                Toggle("Enabled", isOn: targetBinding.isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                TextField("Name", text: targetBinding.name)
                    .textFieldStyle(.plain)
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
            HStack(spacing: 10) {
                Text("Purpose:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                StablePurposeField(placeholder, text: targetBinding.purpose)
                    .accessibilityLabel(placeholder)
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 3)
        .background(dropHighlight(isShown: dropSlot?.targetID == target.id))
        .contentShape(Rectangle())
        .onDrop(
            of: [.reflexTarget],
            delegate: dropDelegate(DropSlot(area: .row, targetID: target.id))
        )
    }

    /// The row under the pointer shows where the dragged target goes.
    private func dropHighlight(isShown: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor.opacity(isShown ? 0.14 : 0))
            .strokeBorder(Color.accentColor.opacity(isShown ? 0.6 : 0))
            .animation(.easeOut(duration: 0.12), value: isShown)
    }

    private func dropDelegate(_ slot: DropSlot) -> TargetDropDelegate {
        TargetDropDelegate(
            slot: slot,
            targets: $state.targets,
            draggedTargetID: $draggedTargetID,
            dropSlot: $dropSlot
        )
    }

    /// An empty badge keeps the trash button in the same column on every row.
    @ViewBuilder
    private func keyBadge(_ number: Int?) -> some View {
        if let number {
            KeyBadge(number: number)
                .accessibilityLabel("Key \(number)")
        } else {
            Color.clear.frame(width: 22, height: 22)
        }
    }

    /// The chooser numbers the targets it can show, so a disabled or missing browser has no key.
    private func shortcutNumbers() -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for (index, target) in state.availableTargets.prefix(ChooserView.shortcutKeyCount).enumerated() {
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
