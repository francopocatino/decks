import Foundation

enum GitProvider: String, Codable, CaseIterable, Identifiable {
    case github, gitlab, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .other: "Other"
        }
    }
}

enum AccountMode: String, Codable, CaseIterable, Identifiable {
    case login, apiKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .login: "Claude login"
        case .apiKey: "API key"
        }
    }
}

enum ConnectorKind: String, Codable, CaseIterable, Identifiable {
    case claude, openai, github, gitlab

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude"
        case .openai: "OpenAI"
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .openai: "brain"
        case .github, .gitlab: "arrow.triangle.branch"
        }
    }

    var isLLM: Bool { self == .claude || self == .openai }

    var defaultModel: String {
        switch self {
        case .claude: "claude-opus-4-8"
        case .openai: "gpt-4o"
        case .github, .gitlab: ""
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ConnectorKind
    var mode: AccountMode
    var model: String

    init(name: String, kind: ConnectorKind = .claude) {
        id = UUID()
        self.name = name
        self.kind = kind
        mode = kind == .claude ? .login : .apiKey
        model = kind.defaultModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(ConnectorKind.self, forKey: .kind) ?? .claude
        mode = try container.decodeIfPresent(AccountMode.self, forKey: .mode) ?? .login
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModel
    }
}

struct DeckProfile: Codable, Hashable {
    var accountID: UUID?
    var gitConnectorID: UUID?
    var gitProvider: GitProvider
    var authorEmail: String
    var folders: [String]
    var instructions: String

    init() {
        accountID = nil
        gitConnectorID = nil
        gitProvider = .github
        authorEmail = ""
        folders = []
        instructions = ""
    }
}
