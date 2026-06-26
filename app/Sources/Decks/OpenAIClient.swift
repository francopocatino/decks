import Foundation

struct OpenAIClient {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case let .http(code, body): "OpenAI API error \(code): \(body)"
            case .malformed: "Could not read the API response."
            }
        }
    }

    func reply(system: String, history: [ChatMessage], apiKey: String, model: String) async throws -> AIReply {
        guard let endpoint = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw ClientError.malformed
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var turns = [Turn(role: "system", content: system)]
        turns.append(contentsOf: history.map { Turn(role: $0.role, content: $0.text) })
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: turns))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.malformed }
        guard http.statusCode == 200 else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
            let choice = decoded.choices.first,
            let text = choice.message.content
        else { throw ClientError.malformed }
        return AIReply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), truncated: choice.finishReason == "length")
    }

    func validate(apiKey: String) async -> Result<Void, ClientError> {
        guard let endpoint = URL(string: "https://api.openai.com/v1/models") else {
            return .failure(.malformed)
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        let messages: [Turn]
    }

    private struct Turn: Encodable {
        let role: String
        let content: String
    }

    private struct ResponseBody: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct Message: Decodable {
            let content: String?
        }
    }
}
