import AppKit
import Foundation

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

struct BrowserLauncher {
    static func isValidProfileDirectory(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
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

        if let profile = target.chromiumProfileDirectory, !profile.isEmpty {
            guard Self.isValidProfileDirectory(profile) else {
                throw BrowserLaunchError.invalidProfileDirectory
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [
                "-na", applicationURL.path, "--args", "--profile-directory=\(profile)", originalURL.absoluteString,
            ]
            let terminationStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { completedProcess in
                    continuation.resume(returning: completedProcess.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            guard terminationStatus == 0 else {
                throw BrowserLaunchError.launchFailed("open exited with status \(terminationStatus)")
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        do {
            _ = try await NSWorkspace.shared.open(
                [originalURL],
                withApplicationAt: applicationURL,
                configuration: configuration
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
