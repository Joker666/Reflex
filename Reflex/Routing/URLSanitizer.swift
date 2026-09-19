import Foundation

enum URLSanitizer {
    static func sanitize(
        _ url: URL,
        sourceApplicationBundleIdentifier: String? = nil
    ) -> RoutingContext? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
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
            sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier
        )
    }
}
