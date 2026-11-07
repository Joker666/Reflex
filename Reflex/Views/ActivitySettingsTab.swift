import SwiftUI

struct ActivitySettingsTab: View {
    @ObservedObject var activityLog: ActivityLogStore
    @State private var activitySearchText = ""
    @State private var isShowingClearConfirmation = false
    @State private var expandedEntryIDs: Set<UUID> = []

    private var filteredActivityEntries: [ActivityLogEntry] {
        let trimmed = activitySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return activityLog.entries }
        return activityLog.entries.filter { entry in
            entry.host.lowercased().contains(trimmed) ||
            entry.path.lowercased().contains(trimmed) ||
            entry.targetName.lowercased().contains(trimmed) ||
            (entry.sourceApplicationName?.lowercased().contains(trimmed) ?? false) ||
            entry.outcome.rawValue.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Toggle("Record routing activity", isOn: $activityLog.isLoggingEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13, weight: .medium))

                if activityLog.isLoggingEnabled {
                    Spacer()

                    Picker("Retention:", selection: $activityLog.retentionPeriod) {
                        ForEach(ActivityRetentionPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .frame(width: 150)

                    Button("Clear Log…") {
                        isShowingClearConfirmation = true
                    }
                    .disabled(activityLog.entries.isEmpty)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if !activityLog.isLoggingEnabled {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Routing Activity is Disabled")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Turn on activity logging to see recently routed links and TypeSafe Jev decision scores for transparency.\n\nAll data is stored locally on your Mac. Reflex never persists full query parameters, tracking tokens, fragments, or page data.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Turn On Activity Logging") {
                        activityLog.isLoggingEnabled = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                        TextField("Filter by host, target, app, or outcome…", text: $activitySearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !activitySearchText.isEmpty {
                            Button {
                                activitySearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)

                    Divider()

                    if activityLog.entries.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No Routing Activity Yet")
                                .font(.system(size: 14, weight: .medium))
                            Text("When you click web links, their routing outcomes and Jev evaluation scores will appear here.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 360)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 60)
                    } else if filteredActivityEntries.isEmpty {
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "questionmark.folder")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No Matching Entries")
                                .font(.system(size: 14, weight: .medium))
                            Text("No activity matches \"\(activitySearchText)\".")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 60)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredActivityEntries) { entry in
                                    activityRow(entry: entry)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear Activity Log?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                activityLog.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all locally recorded routing history and Jev confidence scores.")
        }
    }

    @ViewBuilder
    private func activityRow(entry: ActivityLogEntry) -> some View {
        let isExpanded = expandedEntryIDs.contains(entry.id)

        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedEntryIDs.remove(entry.id)
                    } else {
                        expandedEntryIDs.insert(entry.id)
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    outcomeBadge(for: entry)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entry.host)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(entry.path)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack(spacing: 6) {
                            if let sourceApp = entry.sourceApplicationName ?? entry.sourceApplicationBundleIdentifier {
                                Text(sourceApp)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.targetName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Link Context")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(entry.scheme)://\(entry.host)\(entry.path)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        if !entry.queryParameterNames.isEmpty {
                            Text("Query parameters: \(entry.queryParameterNames.joined(separator: ", ")) (values omitted for privacy)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let confidence = entry.jevConfidence {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Jev AI Evaluation")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Confidence: \(SettingsText.percent(confidence))")
                                    .font(.system(size: 11, weight: .semibold))
                                if let threshold = entry.autoRouteThreshold {
                                    Text("(Threshold: \(SettingsText.percent(threshold)))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !entry.targetScores.isEmpty {
                                VStack(spacing: 5) {
                                    ForEach(entry.targetScores) { score in
                                        targetScoreBar(score: score, entry: entry)
                                    }
                                }
                            }

                            if let suggestedID = entry.suggestedTargetID,
                               suggestedID != entry.targetID {
                                let suggestedName = entry.targetScores.first(where: { $0.targetID == suggestedID })?.targetName ?? "suggested target"
                                Label("Manual override: you chose \(entry.targetName) instead of \(suggestedName)", systemImage: "arrow.triangle.swap")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(fallbackExplanation(for: entry.outcome))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 6)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func targetScoreBar(score: TargetScore, entry: ActivityLogEntry) -> some View {
        let isChosen = score.targetID == entry.targetID
        let isSuggested = score.targetID == entry.suggestedTargetID

        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(score.targetName)
                    .font(.system(size: 11, weight: isChosen ? .semibold : .regular))
                    .foregroundStyle(isChosen ? .primary : .secondary)
                    .lineLimit(1)
                if isChosen {
                    Text("(Opened)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                } else if isSuggested {
                    Text("(Suggested)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 170, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(isChosen ? Color.accentColor : Color.primary.opacity(0.35))
                        .frame(width: max(3, geo.size.width * CGFloat(min(max(score.score, 0), 1))), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            Text(SettingsText.percent(score.score))
                .font(.system(size: 11, weight: isChosen ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isChosen ? .primary : .secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func outcomeBadge(for entry: ActivityLogEntry) -> some View {
        let (title, systemImage, tint): (String, String, Color) = switch entry.outcome {
        case .autoRouted:
            (entry.jevConfidence.map { "Auto \(SettingsText.percent($0))" } ?? "Auto", "sparkles", .green)
        case .manualChoice: ("Chooser", "hand.tap.fill", .blue)
        case .modifierBypass: ("Shortcut", "command", .secondary)
        case .singleTargetBypass: ("Direct", "arrow.right.circle.fill", .secondary)
        case .fallback: ("Fallback", "questionmark.circle.fill", .orange)
        }
        return Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint == .secondary ? Color.primary.opacity(0.08) : tint.opacity(0.12), in: Capsule())
    }

    private func fallbackExplanation(for outcome: RoutingOutcome) -> String {
        switch outcome {
        case .modifierBypass:
            return "Automatic selection was skipped because the chooser shortcut modifier was held."
        case .singleTargetBypass:
            return "Bypassed Jev because only one browser target is enabled."
        case .fallback:
            return "Automatic selection was unavailable (no API key, disabled, network error, or timeout)."
        default:
            return "Target opened."
        }
    }
}
