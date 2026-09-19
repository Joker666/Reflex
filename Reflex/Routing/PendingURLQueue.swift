import Foundation

struct PendingLink: Equatable {
    var url: URL
    var sourceApplicationBundleIdentifier: String?
}

struct PendingURLQueue: Equatable {
    private(set) var current: PendingLink?
    private(set) var waiting: [PendingLink] = []

    mutating func enqueue(_ url: URL, sourceApplicationBundleIdentifier: String? = nil) {
        let link = PendingLink(
            url: url,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier
        )
        guard current != nil else {
            current = link
            return
        }
        waiting.append(link)
    }

    @discardableResult
    mutating func advance() -> PendingLink? {
        current = waiting.isEmpty ? nil : waiting.removeFirst()
        return current
    }
}
