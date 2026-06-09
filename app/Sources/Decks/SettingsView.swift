import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @Environment(DecksStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            List(selection: sectionSelection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch store.settingsSection {
                case .general: GeneralSettingsView()
                case .connectors: ConnectorsView()
                case .decks: DecksSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
    }

    private var sectionSelection: Binding<SettingsSection?> {
        Binding(
            get: { store.settingsSection },
            set: { if let value = $0 { store.settingsSection = value } }
        )
    }
}

struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

struct ConnectorsView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var editing: Account?

    var body: some View {
        Form {
            connectorSection("AI", footer: "Claude and OpenAI power Ask and the MCP server.", kinds: [.claude, .openai])
            connectorSection("Git", footer: "Tokens that enrich the worklog with your PRs and issues.", kinds: [.github, .gitlab])
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { account in
            ConnectorEditor(account: binding(for: account.id)) { editing = nil }
                .environment(identity)
        }
    }

    @ViewBuilder
    private func connectorSection(_ title: String, footer: String, kinds: [ConnectorKind]) -> some View {
        let items = identity.accounts.filter { kinds.contains($0.kind) }
        Section {
            if items.isEmpty {
                Text("None yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { account in
                ConnectorRow(account: account) {
                    editing = account
                } onDelete: {
                    identity.deleteAccount(account.id)
                }
            }
            Menu {
                ForEach(kinds) { kind in
                    Button {
                        editing = identity.addAccount(name: kind.label, kind: kind)
                    } label: {
                        Label(kind.label, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label("New \(title) connector", systemImage: "plus")
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func binding(for id: UUID) -> Binding<Account> {
        Binding(
            get: { identity.accounts.first { $0.id == id } ?? Account(name: "") },
            set: { identity.updateAccount($0) }
        )
    }
}

private struct ConnectorRow: View {
    let account: Account
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Label(account.name.isEmpty ? account.kind.label : account.name, systemImage: account.kind.symbol)
            Spacer()
            Text(account.kind.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

struct DecksSettingsView: View {
    @Environment(DecksStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            List(selection: deckSelection) {
                ForEach(store.topLevelVisibleDecks()) { deck in
                    let children = store.visibleChildren(of: deck.slug)
                    if children.isEmpty {
                        deckRow(deck)
                    } else {
                        DisclosureGroup {
                            ForEach(children) { child in deckRow(child) }
                        } label: {
                            deckRow(deck)
                        }
                    }
                }
                if !store.archivedDecks.isEmpty {
                    Section("Archived") {
                        ForEach(store.archivedDecks) { deck in deckRow(deck) }
                    }
                }
            }
            .frame(width: 200)

            Divider()

            Group {
                if let slug = store.settingsDeck, let deck = store.deck(slug) {
                    DeckSettingsForm(deck: deck).id(slug)
                } else {
                    ContentUnavailableView("Select a deck", systemImage: "rectangle.stack")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if store.settingsDeck == nil {
                store.settingsDeck = store.topLevelVisibleDecks().first?.slug
            }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        Label(deck.name, systemImage: deck.isArchived ? "archivebox" : "rectangle.stack")
            .tag(deck.slug)
    }

    private var deckSelection: Binding<String?> {
        Binding(
            get: { store.settingsDeck },
            set: { store.settingsDeck = $0 }
        )
    }
}

private struct ConnectorEditor: View {
    @Environment(IdentityStore.self) private var identity
    @Binding var account: Account
    var onClose: () -> Void

    @State private var key = ""
    @State private var status = Status.idle
    @State private var registered = false

    private enum Status: Equatable {
        case idle, checking, ok, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $account.name)
                } header: {
                    Label(account.kind.label, systemImage: account.kind.symbol)
                }

                if account.kind == .claude {
                    Section("Mode") {
                        Picker("Mode", selection: $account.mode) {
                            Text("Claude Code (MCP)").tag(AccountMode.login)
                            Text("Anthropic API key").tag(AccountMode.apiKey)
                        }
                    }
                }

                if needsKey {
                    Section {
                        if account.kind.isLLM {
                            TextField("Model", text: $account.model)
                        }
                        SecureField(secretPlaceholder, text: $key)
                        HStack {
                            Button("Verify & save", action: verify)
                                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || status == .checking)
                            statusLabel
                            Spacer()
                            if let url = secretURL {
                                Button(createLabel) { NSWorkspace.shared.open(url) }
                            }
                        }
                    } header: {
                        Text(secretLabel)
                    } footer: {
                        Text(secretHelp)
                    }
                } else {
                    Section {
                        Text("This deck is driven by Claude Code or Desktop through the MCP server. It uses whatever account that client is logged into — no key is stored here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Copy Claude Code command", action: copyCommand)
                            Spacer()
                            if registered {
                                Label("Registered", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Delete", role: .destructive) {
                    identity.deleteAccount(account.id)
                    onClose()
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 360)
        .onAppear {
            key = identity.apiKey(for: account.id)
            registered = ClaudeCode.decksRegistered()
        }
    }

    private var needsKey: Bool {
        switch account.kind {
        case .openai, .github, .gitlab: true
        case .claude: account.mode == .apiKey
        }
    }

    private var secretLabel: String {
        switch account.kind {
        case .claude: "Anthropic API key"
        case .openai: "OpenAI API key"
        case .github: "GitHub token"
        case .gitlab: "GitLab token"
        }
    }

    private var secretPlaceholder: String {
        switch account.kind {
        case .claude: "sk-ant-…"
        case .openai: "sk-…"
        case .github: "ghp_… or github_pat_…"
        case .gitlab: "glpat-…"
        }
    }

    private var secretHelp: String {
        switch account.kind {
        case .claude: "Anthropic API key from the console. Used for in-app Ask."
        case .openai: "OpenAI API key. Used for in-app Ask."
        case .github: "Personal access token with read access to repos' pull requests and issues (classic: repo / public_repo)."
        case .gitlab: "Personal access token with the read_api scope."
        }
    }

    private var secretURL: URL? {
        switch account.kind {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .github: URL(string: "https://github.com/settings/tokens")
        case .gitlab: URL(string: "https://gitlab.com/-/user_settings/personal_access_tokens")
        }
    }

    private var createLabel: String {
        account.kind.isLLM ? "Get API key…" : "Create token…"
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func verify() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        identity.setAPIKey(trimmed, for: account.id)
        status = .checking
        Task {
            let result: Result<Void, Error>
            switch account.kind {
            case .claude:
                result = (await AnthropicClient().validate(apiKey: trimmed)).mapError { $0 as Error }
            case .openai:
                result = (await OpenAIClient().validate(apiKey: trimmed)).mapError { $0 as Error }
            case .github, .gitlab:
                result = await verifyGitToken(trimmed)
            }
            switch result {
            case .success: status = .ok
            case let .failure(error): status = .failed(error.localizedDescription)
            }
        }
    }

    private func verifyGitToken(_ token: String) async -> Result<Void, Error> {
        let endpoint = account.kind == .github
            ? "https://api.github.com/user"
            : "https://gitlab.com/api/v4/user"
        guard let url = URL(string: endpoint) else { return .failure(URLError(.badURL)) }
        var request = URLRequest(url: url)
        if account.kind == .github {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        } else {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }
        guard
            let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { return .failure(URLError(.cannotConnectToHost)) }
        return http.statusCode == 200 ? .success(()) : .failure(URLError(.userAuthenticationRequired))
    }

    private func copyCommand() {
        let bin = ("~/.cargo/bin/decks-mcp" as NSString).expandingTildeInPath
        let command = "claude mcp add decks -- \(bin)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
