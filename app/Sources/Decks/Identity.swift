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

struct Account: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var mode: AccountMode
    var model: String

    init(name: String) {
        id = UUID()
        self.name = name
        mode = .login
        model = "claude-opus-4-8"
    }
}

struct DeckProfile: Codable, Hashable {
    var accountID: UUID?
    var gitProvider: GitProvider
    var authorEmail: String
    var folders: [String]

    init() {
        accountID = nil
        gitProvider = .github
        authorEmail = ""
        folders = []
    }
}
