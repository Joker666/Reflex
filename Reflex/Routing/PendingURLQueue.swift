import Foundation

struct PendingLink: Equatable {
    var url: URL
    var sourceApplicationBundleIdentifier: String?
    /// The user held Option, so Reflex shows the chooser and does not route by itself.
    var asksForChooser = false
}

struct PendingURLQueue: Equatable {
    private(set) var current: PendingLink?
    private(set) var waiting: [PendingLink] = []

    mutating func enqueue(
        _ url: URL,
        sourceApplicationBundleIdentifier: String? = nil,
        asksForChooser: Bool = false
    ) {
        let link = PendingLink(
            url: url,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            asksForChooser: asksForChooser
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
