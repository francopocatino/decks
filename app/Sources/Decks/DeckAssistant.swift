import Foundation

// An LLM reply plus whether the model stopped because it hit the output token
// cap. Callers that overwrite their source (Notes "Polish") must refuse a
// truncated result; callers that append (Daily "Draft") can use it as is.
struct AIReply {
    var text: String
    var truncated: Bool
}

@MainActor
enum DeckAssistant {
    static func connector(for slug: String, parent: String?, identity: IdentityStore) -> Account? {
        guard let account = identity.accounts.first(where: { $0.id == identity.effectiveAccountID(for: slug, parent: parent) }),
              account.kind.isLLM,
              account.kind == .openai || account.mode == .apiKey
        else { return nil }
        return account
    }

    static func hasBackend(for slug: String, parent: String?, identity: IdentityStore) -> Bool {
        connector(for: slug, parent: parent, identity: identity) != nil || AppleIntelligence.isAvailable
    }

    static func run(system: String, user: String, slug: String, parent: String?, identity: IdentityStore) async throws -> AIReply {
        let preamble = identity.effectiveInstructions(for: slug, parent: parent)
        let fullSystem = preamble.isEmpty ? system : "\(preamble)\n\n\(system)"

        guard let account = connector(for: slug, parent: parent, identity: identity) else {
            guard AppleIntelligence.isAvailable else { throw AssistantError.noConnector }
            return AIReply(text: try await AppleIntelligence.reply(system: fullSystem, user: user), truncated: false)
        }
        let key = identity.apiKey(for: account.id)
        guard !key.isEmpty else { throw AssistantError.noKey }
        let history = [ChatMessage(role: "user", text: user)]

        if account.kind == .openai {
            return try await OpenAIClient().reply(system: fullSystem, history: history, apiKey: key, model: account.model)
        }
        return try await AnthropicClient().reply(system: fullSystem, history: history, apiKey: key, model: account.model)
    }

    enum AssistantError: LocalizedError {
        case noConnector, noKey

        var errorDescription: String? {
            switch self {
            case .noConnector: "This deck has no API-key AI connector."
            case .noKey: "This connector has no API key set."
            }
        }
    }
}
