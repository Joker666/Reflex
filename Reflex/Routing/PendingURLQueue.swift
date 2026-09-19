import Foundation

struct PendingURLQueue: Equatable {
    private(set) var current: URL?
    private(set) var waiting: [URL] = []

    mutating func enqueue(_ url: URL) {
        guard current != nil else {
            current = url
            return
        }
        waiting.append(url)
    }

    @discardableResult
    mutating func advance() -> URL? {
        current = waiting.isEmpty ? nil : waiting.removeFirst()
        return current
    }
}
