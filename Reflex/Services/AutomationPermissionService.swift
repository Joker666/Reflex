import AppKit
import Carbon
import Foundation

enum AutomationPermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

struct AutomationPermissionService {
    static let diaBundleIdentifier = "company.thebrowser.dia"

    static func requestDiaAccess() async -> AutomationPermissionState {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: diaBundleIdentifier
        ) else {
            return .unavailable
        }

        if NSRunningApplication.runningApplications(withBundleIdentifier: diaBundleIdentifier).isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: configuration
                )
            } catch {
                return .unavailable
            }
        }

        return await Task.detached(priority: .userInitiated) {
            permissionState(askUserIfNeeded: true)
        }.value
    }

    private nonisolated static func permissionState(
        askUserIfNeeded: Bool
    ) -> AutomationPermissionState {
        let identifier = Data(diaBundleIdentifier.utf8)
        var target = AEAddressDesc()
        let createStatus = identifier.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                identifier.count,
                &target
            )
        }
        guard createStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
        switch status {
        case noErr:
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }
}
