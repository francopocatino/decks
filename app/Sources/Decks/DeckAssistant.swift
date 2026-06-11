import Foundation

@MainActor
enum DeckAssistant {
    static func connector(for slug: String, identity: IdentityStore) -> Account? {
        guard let account = identity.accounts.first(where: { $0.id == identity.profile(slug).accountID }),
              account.kind.isLLM,
              account.kind == .openai || account.mode == .apiKey
        else { return nil }
        return account
    }

    static func hasBackend(for slug: String, identity: IdentityStore) -> Bool {
        connector(for: slug, identity: identity) != nil || AppleIntelligence.isAvailable
    }

    static func run(system: String, user: String, slug: String, identity: IdentityStore) async throws -> String {
        let preamble = instructions(for: slug, identity: identity)
        let fullSystem = preamble.isEmpty ? system : "\(preamble)\n\n\(system)"

        guard let account = connector(for: slug, identity: identity) else {
            guard AppleIntelligence.isAvailable else { throw AssistantError.noConnector }
            return try await AppleIntelligence.reply(system: fullSystem, user: user)
        }
        let key = identity.apiKey(for: account.id)
        guard !key.isEmpty else { throw AssistantError.noKey }
        let history = [ChatMessage(role: "user", text: user)]

        if account.kind == .openai {
            return try await OpenAIClient().reply(system: fullSystem, history: history, apiKey: key, model: account.model)
        }
        return try await AnthropicClient().reply(system: fullSystem, history: history, apiKey: key, model: account.model)
    }

    private static func instructions(for slug: String, identity: IdentityStore) -> String {
        identity.profile(slug).instructions.trimmingCharacters(in: .whitespacesAndNewlines)
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
