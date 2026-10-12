import AppKit
import Foundation

protocol BrowserLaunching: Sendable {
    func isAvailable(_ target: BrowserTarget) -> Bool
    func icon(for target: BrowserTarget) -> NSImage?
    func open(_ originalURL: URL, in target: BrowserTarget) async throws
}

enum BrowserLaunchError: LocalizedError, Equatable {
    case applicationUnavailable
    case invalidProfileDirectory
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable: "The selected browser is not available."
        case .invalidProfileDirectory: "The profile identifier contains invalid characters."
        case .launchFailed: "Reflex could not open the link in the selected browser."
        }
    }
}

struct BrowserLauncher: BrowserLaunching {
    static func isValidProfileDirectory(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    /// One argument per element, so a URL can never become shell syntax.
    static func profileLaunchArguments(
        applicationPath: String,
        profileDirectory: String,
        url: URL
    ) -> [String] {
        ["-na", applicationPath, "--args", "--profile-directory=\(profileDirectory)", url.absoluteString]
    }

    /// Dia enforces a single running instance and displays an error alert if launched with `open -n`.
    /// Dia's native AppleScript suite supports focusing profiles and creating tabs in that profile.
    static func openInDia(url: URL, profileName: String) -> Bool {
        let escapedURL = appleScriptEscaped(url.absoluteString)
        let escapedProfile = appleScriptEscaped(profileName)

        let script = """
        tell application "Dia"
            activate
            if (count of windows) > 0 then
                try
                    set targetProfile to (first profile of front window whose name is "\(escapedProfile)")
                    tell targetProfile to focus
                    tell targetProfile to make new tab with properties {URL:"\(escapedURL)"}
                    return true
                on error
                    make new tab at front window with properties {URL:"\(escapedURL)"}
                    return true
                end try
            else
                open location "\(escapedURL)"
                return true
            end if
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    /// The value goes inside a quoted AppleScript string, so it can never end that string.
    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func isAvailable(_ target: BrowserTarget) -> Bool {
        applicationURL(for: target) != nil
    }

    func icon(for target: BrowserTarget) -> NSImage? {
        applicationURL(for: target).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func open(_ originalURL: URL, in target: BrowserTarget) async throws {
        guard let applicationURL = applicationURL(for: target) else {
            throw BrowserLaunchError.applicationUnavailable
        }

        if target.bundleIdentifier == SupportedBrowser.diaBundleIdentifier {
            if let profile = BrowserTarget.profilePart(of: target.name), !profile.isEmpty {
                if Self.openInDia(url: originalURL, profileName: profile) {
                    return
                }
            }
            try await openWithWorkspace(originalURL, applicationURL: applicationURL)
            return
        }

        if SupportedBrowser.supportsChromiumProfiles(target.bundleIdentifier),
           let profile = target.chromiumProfileDirectory, !profile.isEmpty {
            guard Self.isValidProfileDirectory(profile) else {
                throw BrowserLaunchError.invalidProfileDirectory
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = Self.profileLaunchArguments(
                applicationPath: applicationURL.path,
                profileDirectory: profile,
                url: originalURL
            )
            let terminationStatus: Int32 = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { completedProcess in
                        continuation.resume(returning: completedProcess.terminationStatus)
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
            try Task.checkCancellation()
            guard terminationStatus == 0 else {
                throw BrowserLaunchError.launchFailed("open exited with status \(terminationStatus)")
            }
            return
        }

        try await openWithWorkspace(originalURL, applicationURL: applicationURL)
    }

    private func openWithWorkspace(_ url: URL, applicationURL: URL) async throws {
        do {
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } catch {
            throw BrowserLaunchError.launchFailed(error.localizedDescription)
        }
    }

    func applicationURL(for target: BrowserTarget) -> URL? {
        if target.bundleIdentifier.hasPrefix("/") {
            let url = URL(fileURLWithPath: target.bundleIdentifier).standardizedFileURL
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
    }
}
