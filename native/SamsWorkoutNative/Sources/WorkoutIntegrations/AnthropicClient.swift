import Foundation

public struct AnthropicGenerationResult: Equatable, Sendable {
    public let text: String
    public let model: String
    public let stopReason: String?

    public init(text: String, model: String, stopReason: String?) {
        self.text = text
        self.model = model
        self.stopReason = stopReason
    }
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [Message]
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }

    let model: String
    let stop_reason: String?
    let content: [ContentItem]
}

public enum AnthropicClientError: Error, Equatable {
    case emptyResponse
}

public struct AnthropicClient: Sendable {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let httpClient: HTTPClient
    private let baseURL: URL

    public init(
        apiKey: String,
        model: String,
        maxTokens: Int,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    public func generatePlan(systemPrompt: String?, userPrompt: String) async throws -> AnthropicGenerationResult {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: [.init(role: "user", content: userPrompt)]
        )

        let request = HTTPRequest(
            method: "POST",
            url: baseURL.appendingPathComponent("v1/messages"),
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            ],
            body: try JSONEncoder().encode(payload)
        )

        let response = try await httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.invalidStatus(response.statusCode, String(data: response.body, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: response.body)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw AnthropicClientError.emptyResponse
        }

        return AnthropicGenerationResult(text: text, model: decoded.model, stopReason: decoded.stop_reason)
    }
}
