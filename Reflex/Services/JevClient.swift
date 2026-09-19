import Foundation

enum JevClientError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
}

struct JevChoiceMapping: Equatable {
    var keyToTargetID: [String: UUID]
}

protocol JevTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionJevTransport: JevTransport {
    var session: URLSession

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

private struct JevRequest: Encodable {
    struct State: Encodable {
        struct Link: Encodable {
            var scheme: String
            var host: String
            var path: String
            var queryParameterNames: [String]
        }
        struct Target: Encodable {
            var key: String
            var name: String
            var purpose: String
        }
        var link: Link
        var sourceApplicationBundleIdentifier: String?
        var targets: [Target]
    }
    struct Questions: Encodable {
        struct TargetQuestion: Encodable {
            var type = "choice"
            var instructions: String
            var criteria: [String: String]
        }
        var target: TargetQuestion
    }
    var state: State
    var model: String
    var questions: Questions
}

private struct JevResponse: Decodable {
    struct Answers: Decodable {
        struct Target: Decodable {
            var choice: String
            var probabilities: [String: Double]
            var confidence: Double?
        }
        var target: Target
    }
    var answers: Answers
}

struct JevClient {
    static let openRouterEndpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    static let model = "~typesafe/jev-latest"

    var endpoint = Self.openRouterEndpoint
    var transport: any JevTransport

    init(endpoint: URL = Self.openRouterEndpoint, transport: (any JevTransport)? = nil) {
        self.endpoint = endpoint
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 1.5
            configuration.timeoutIntervalForResource = 1.5
            self.transport = URLSessionJevTransport(session: URLSession(configuration: configuration))
        }
    }

    func makeRequest(
        context: RoutingContext,
        targets: [BrowserTarget],
        apiKey: String
    ) throws -> (URLRequest, JevChoiceMapping) {
        guard !targets.isEmpty else { throw JevClientError.invalidRequest }
        var mapping: [String: UUID] = [:]
        var requestTargets: [JevRequest.State.Target] = []
        var criteria: [String: String] = [:]
        for (index, target) in targets.enumerated() {
            let key = "target_\(index)"
            mapping[key] = target.id
            requestTargets.append(.init(key: key, name: target.name, purpose: target.purpose))
            criteria[key] = "\(target.name): \(target.purpose)"
        }
        let body = JevRequest(
            state: .init(
                link: .init(
                    scheme: context.scheme,
                    host: context.host,
                    path: context.path,
                    queryParameterNames: context.queryParameterNames
                ),
                sourceApplicationBundleIdentifier: context.sourceApplicationBundleIdentifier,
                targets: requestTargets
            ),
            model: Self.model,
            questions: .init(
                target: .init(
                    instructions: "Which enabled browser target is the best place to open `link`, considering the source application and each target's stated purpose?",
                    criteria: criteria
                )
            )
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 1.5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return (request, JevChoiceMapping(keyToTargetID: mapping))
    }

    func decide(
        context: RoutingContext,
        targets: [BrowserTarget],
        apiKey: String
    ) async throws -> RouteDecision {
        let (request, mapping) = try makeRequest(context: context, targets: targets, apiKey: apiKey)
        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JevClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw JevClientError.httpStatus(httpResponse.statusCode)
        }
        return try decodeDecision(data, mapping: mapping)
    }

    func decodeDecision(_ data: Data, mapping: JevChoiceMapping) throws -> RouteDecision {
        let answer: JevResponse.Answers.Target
        do {
            answer = try JSONDecoder().decode(JevResponse.self, from: data).answers.target
        } catch {
            throw JevClientError.invalidResponse
        }
        guard let targetID = mapping.keyToTargetID[answer.choice],
              let confidence = answer.confidence,
              confidence.isFinite,
              (0...1).contains(confidence),
              answer.probabilities.values.allSatisfy({ $0.isFinite }) else {
            throw JevClientError.invalidResponse
        }
        return RouteDecision(targetID: targetID, confidence: confidence)
    }
}
