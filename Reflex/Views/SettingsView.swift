import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case targets = "Targets"
    case routing = "AI Routing"
    case activity = "Activity"

    var identifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .targets: return "globe"
        case .routing: return "sparkles"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class SettingsNavigationState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var navigation: SettingsNavigationState
    @ObservedObject var activityLog: ActivityLogStore

    var body: some View {
        Group {
            switch navigation.selectedTab {
            case .general:
                GeneralSettingsTab(state: state)
            case .targets:
                TargetsSettingsTab(state: state)
            case .routing:
                RoutingSettingsTab(state: state)
            case .activity:
                ActivitySettingsTab(activityLog: activityLog)
            }
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: .infinity, minHeight: 450, idealHeight: 520)
    }
}

/// Text styles that the settings tabs share.
enum SettingsText {
    static func gridLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .gridColumnAlignment(.trailing)
            .frame(width: 155, alignment: .trailing)
    }

    static func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(round(value * 100)))%"
    }
}
