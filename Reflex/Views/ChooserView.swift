import AppKit
import SwiftUI

struct ChooserView: View {
    @ObservedObject var state: AppState
    @State private var selectedTargetID: UUID?
    @State private var scrollRequestCount = 0
    @State private var pointerAnchor: NSPoint?
    @FocusState private var isFocused: Bool

    private let panelWidth: CGFloat = 264
    private let rowHeight: CGFloat = 40
    private let rowSpacing: CGFloat = 2
    private let visibleRowLimit = 6

    var body: some View {
        VStack(spacing: 4) {
            if state.isRouting {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .padding(.horizontal, 6)
            }

            if state.availableTargets.isEmpty {
                emptyState
            } else {
                targetList
            }

            if let error = state.launchError {
                statusLine(error, systemImage: "exclamationmark.triangle", tint: .orange)
            } else if state.isJevUnavailable {
                statusLine(
                    "Automatic selection is unavailable",
                    systemImage: "bolt.slash",
                    tint: .secondary
                )
            }
        }
        .padding(6)
        .frame(width: panelWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            resetSelection()
            isFocused = true
        }
        .onChange(of: state.pendingURL) { _, _ in
            resetSelection()
            isFocused = true
        }
        .onChange(of: state.suggestedTargetID) { _, _ in selectSuggestedOrFirstTarget() }
        .onChange(of: state.availableTargets.map(\.id)) { _, _ in selectSuggestedOrFirstTarget() }
        .onMoveCommand(perform: moveSelection)
        .onExitCommand { state.cancelPending() }
        .onKeyPress(.return) {
            guard let target = state.availableTargets.first(where: { $0.id == selectedTargetID }) else {
                return .ignored
            }
            state.openPending(in: target)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { keyPress in
            guard let digit = keyPress.characters.first.flatMap({ Int(String($0)) }),
                  digit >= 1,
                  digit <= state.availableTargets.count else {
                return .ignored
            }
            state.openPending(in: state.availableTargets[digit - 1])
            return .handled
        }
    }

    private var targetList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(Array(state.availableTargets.enumerated()), id: \.element.id) { index, target in
                        row(index: index, target: target).id(target.id)
                    }
                }
            }
            .frame(height: listHeight)
            .scrollDisabled(state.availableTargets.count <= visibleRowLimit)
            .onChange(of: scrollRequestCount) { _, _ in
                guard let selectedTargetID else { return }
                proxy.scrollTo(selectedTargetID)
            }
        }
    }

    private var listHeight: CGFloat {
        let rowCount = min(max(state.availableTargets.count, 1), visibleRowLimit)
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }

    private func row(index: Int, target: BrowserTarget) -> some View {
        let isSelected = selectedTargetID == target.id
        return Button {
            state.openPending(in: target)
        } label: {
            HStack(spacing: 8) {
                Text(target.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if state.suggestedTargetID == target.id {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .opacity(0.8)
                }
                if index < 9 {
                    keyBadge("\(index + 1)", isSelected: isSelected)
                }
                icon(for: target)
            }
            .padding(.horizontal, 8)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            guard isHovering, pointerDidMove() else { return }
            selectedTargetID = target.id
        }
        .accessibilityLabel("Open in \(target.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func keyBadge(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(width: 20, height: 20)
            .background(
                Color.primary.opacity(isSelected ? 0.22 : 0.10),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func icon(for target: BrowserTarget) -> some View {
        if let image = state.icon(for: target) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "globe")
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No browser is available")
                .font(.system(size: 13, weight: .medium))
            Text("Enable an installed browser in Settings. Reflex keeps the link.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink { Text("Open Settings") }
                .controlSize(.small)
        }
        .padding(12)
    }

    private func statusLine(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func resetSelection() {
        select(state.suggestedTargetID ?? state.availableTargets.first?.id)
    }

    /// The list scrolls under a still pointer after a key press, which sends a false hover.
    private func pointerDidMove() -> Bool {
        guard let pointerAnchor else { return true }
        return pointerAnchor != NSEvent.mouseLocation
    }

    private func select(_ targetID: UUID?) {
        selectedTargetID = targetID
        pointerAnchor = NSEvent.mouseLocation
        scrollRequestCount += 1
    }

    private func selectSuggestedOrFirstTarget() {
        let targetIDs = state.availableTargets.map(\.id)
        if let suggestion = state.suggestedTargetID, targetIDs.contains(suggestion) {
            select(suggestion)
        } else if selectedTargetID == nil || !targetIDs.contains(selectedTargetID!) {
            select(targetIDs.first)
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
        select(targetIDs[nextIndex])
    }
}
