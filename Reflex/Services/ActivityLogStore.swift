import Foundation
import Combine
import OSLog

@MainActor
protocol ActivityLogging: AnyObject {
    var isLoggingEnabled: Bool { get }
    func record(_ entry: ActivityLogEntry)
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
    /// Writes run in order off the main actor. A load waits for earlier writes.
    private static let fileQueue = DispatchQueue(label: "com.rafi.Reflex.activity-log")

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
        let fileURL = fileURL
        let result: Result<Data, Error>? = Self.fileQueue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return Result { try Data(contentsOf: fileURL) }
        }
        guard let result else { return }
        do {
            entries = try JSONDecoder().decode([ActivityLogEntry].self, from: result.get())
        } catch {
            ReflexLog.routing.error("Failed to load activity log: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(entries)
        } catch {
            ReflexLog.routing.error("Failed to encode activity log: \(error.localizedDescription, privacy: .private)")
            return
        }
        let fileURL = fileURL
        Self.fileQueue.async {
            do {
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                ReflexLog.routing.error("Failed to save activity log: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
