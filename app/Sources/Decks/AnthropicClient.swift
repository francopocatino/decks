import Foundation

struct AnthropicClient {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case let .http(code, body): "Anthropic API error \(code): \(body)"
            case .malformed: "Could not read the API response."
            }
        }
    }

    func reply(system: String, history: [ChatMessage], apiKey: String, model: String) async throws -> String {
        guard let endpoint = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClientError.malformed
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = RequestBody(
            model: model,
            maxTokens: 4096,
            system: system,
            messages: history.map { Turn(role: $0.role, content: $0.text) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.malformed }
        guard http.statusCode == 200 else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data) else {
            throw ClientError.malformed
        }
        return decoded.content
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validate(apiKey: String) async -> Result<Void, ClientError> {
        guard let endpoint = URL(string: "https://api.anthropic.com/v1/models") else {
            return .failure(.malformed)
        }
        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { return .failure(.malformed) }
        if http.statusCode == 200 {
            return .success(())
        }
        return .failure(.http(http.statusCode, String(data: data, encoding: .utf8) ?? ""))
    }

    private struct RequestBody: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Turn]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct Turn: Encodable {
        let role: String
        let content: String
    }

    private struct ResponseBody: Decodable {
        let content: [Block]

        struct Block: Decodable {
            let type: String
            let text: String?
        }
    }
}
