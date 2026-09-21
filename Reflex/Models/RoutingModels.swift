import AppKit
import Foundation

enum ChooserModifier: String, CaseIterable, Identifiable {
    case option
    case control
    case shift
    case command
    case function = "fn"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .option: "Option"
        case .control: "Control"
        case .shift: "Shift"
        case .command: "Command"
        case .function: "Fn"
        }
    }

    var symbolName: String {
        switch self {
        case .option: "option"
        case .control: "control"
        case .shift: "shift"
        case .command: "command"
        case .function: "fn"
        }
    }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .command: .command
        case .function: .function
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(eventFlag)
    }

    static func fromStoredValue(_ value: String?) -> ChooserModifier {
        value.flatMap(ChooserModifier.init(rawValue:)) ?? .option
    }
}

struct RoutingContext: Codable, Equatable {
    var scheme: String
    var host: String
    var path: String
    var queryParameterNames: [String]
    var sourceApplicationBundleIdentifier: String?
    var sourceApplicationName: String?
}

struct RouteDecision: Equatable {
    var targetID: UUID
    var confidence: Double
    var probabilities: [UUID: Double]

    init(targetID: UUID, confidence: Double, probabilities: [UUID: Double] = [:]) {
        self.targetID = targetID
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

enum RoutingAction: Equatable {
    case setup
    case open(UUID)
    case choose(suggestedTargetID: UUID?)
}
