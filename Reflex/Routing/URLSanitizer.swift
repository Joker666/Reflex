import Foundation

extension URL {
    var isHTTPOrHTTPS: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

enum URLSanitizer {
    static func sanitize(
        _ url: URL,
        sourceApplicationBundleIdentifier: String? = nil,
        sourceApplicationName: String? = nil
    ) -> RoutingContext? {
        guard url.isHTTPOrHTTPS,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host else {
            return nil
        }

        var seenNames = Set<String>()
        let queryParameterNames = (components.queryItems ?? []).compactMap { item in
            seenNames.insert(item.name).inserted ? item.name : nil
        }
        return RoutingContext(
            scheme: scheme,
            host: host,
            path: components.path.isEmpty ? "/" : components.path,
            queryParameterNames: queryParameterNames,
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier,
            sourceApplicationName: sourceApplicationName
        )
    }
}
