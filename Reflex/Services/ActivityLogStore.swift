import Foundation
import Combine
import OSLog

@MainActor
protocol ActivityLogging: AnyObject {
    var isLoggingEnabled: Bool { get }
    func record(_ entry: ActivityLogEntry)
    func clear()
}

@MainActor
final class ActivityLogStore: ObservableObject, ActivityLogging {
    @Published private(set) var entries: [ActivityLogEntry] = []
    @Published var isLoggingEnabled: Bool {
        didSet {
            defaults.set(isLoggingEnabled, forKey: isLoggingEnabledKey)
        }
    }
    @Published var retentionPeriod: ActivityRetentionPeriod {
        didSet {
            defaults.set(retentionPeriod.rawValue, forKey: retentionPeriodKey)
            prune()
            save()
        }
    }

    private let defaults: UserDefaults
    private let fileURL: URL
    private let maxEntries = 2_000
    private let isLoggingEnabledKey = "isActivityLoggingEnabled"
    private let retentionPeriodKey = "activityLogRetentionDays"

    init(
        defaults: UserDefaults = .standard,
        fileURL: URL? = nil
    ) {
        self.defaults = defaults
        self.isLoggingEnabled = defaults.bool(forKey: isLoggingEnabledKey)
        let storedDays = defaults.integer(forKey: retentionPeriodKey)
        self.retentionPeriod = ActivityRetentionPeriod(rawValue: storedDays) ?? .sevenDays

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let reflexFolder = appSupport.appendingPathComponent("Reflex", isDirectory: true)
            try? FileManager.default.createDirectory(at: reflexFolder, withIntermediateDirectories: true)
            self.fileURL = reflexFolder.appendingPathComponent("activity_log.json")
        }

        load()
        prune()
    }

    func record(_ entry: ActivityLogEntry) {
        guard isLoggingEnabled else { return }
        entries.insert(entry, at: 0)
        prune()
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-retentionPeriod.timeInterval)
        entries.removeAll { $0.timestamp < cutoff }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([ActivityLogEntry].self, from: data)
            entries = loaded
        } catch {
            ReflexLog.routing.error("Failed to load activity log: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            ReflexLog.routing.error("Failed to save activity log: \(error.localizedDescription, privacy: .private)")
        }
    }
}
