import Foundation

public struct AnthropicGenerationResult: Equatable, Sendable {
    public let text: String
    public let model: String
    public let stopReason: String?
    public let inputTokens: Int
    public let outputTokens: Int

    public init(text: String, model: String, stopReason: String?, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.text = text
        self.model = model
        self.stopReason = stopReason
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let max_tokens: Int
    let stream: Bool
    let system: String?
    let messages: [Message]
}

public enum AnthropicClientError: Error, Equatable {
    case emptyResponse
    case invalidResponse
}

public struct AnthropicClient: Sendable {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let session: URLSession
    private let baseURL: URL

    public init(
        apiKey: String,
        model: String,
        maxTokens: Int,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.session = session
        self.baseURL = baseURL
    }

    public func generatePlan(systemPrompt: String?, userPrompt: String) async throws -> AnthropicGenerationResult {
        let payload = AnthropicMessagesRequest(
            model: model,
            max_tokens: maxTokens,
            stream: true,
            system: systemPrompt,
            messages: [.init(role: "user", content: userPrompt)]
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            throw HTTPClientError.invalidStatus(httpResponse.statusCode, String(data: errorData, encoding: .utf8) ?? "")
        }

        var fullText = ""
        var inputTokens = 0
        var outputTokens = 0
        var responseModel = model
        var stopReason: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = event["type"] as? String
            else { continue }

            switch eventType {
            case "message_start":
                if let message = event["message"] as? [String: Any] {
                    responseModel = (message["model"] as? String) ?? model
                    if let usage = message["usage"] as? [String: Any] {
                        inputTokens = (usage["input_tokens"] as? Int) ?? 0
                    }
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    fullText += text
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any] {
                    stopReason = delta["stop_reason"] as? String
                }
                if let usage = event["usage"] as? [String: Any] {
                    outputTokens = (usage["output_tokens"] as? Int) ?? 0
                }
            default:
                break
            }
        }

        if fullText.isEmpty {
            throw AnthropicClientError.emptyResponse
        }

        return AnthropicGenerationResult(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            model: responseModel,
            stopReason: stopReason,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
