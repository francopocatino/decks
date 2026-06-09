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
        NavigationSplitView {
            List(selection: sectionSelection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch store.settingsSection {
            case .general: GeneralSettingsView()
            case .connectors: ConnectorsView()
            case .decks: DecksSettingsView()
            }
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
        .navigationTitle("General")
    }
}

struct ConnectorsView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var newAccount = ""

    var body: some View {
        Form {
            Section {
                if identity.accounts.isEmpty {
                    Text("No accounts yet. Add one and point decks at it; several decks can share the same account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(identity.accounts) { account in
                    AccountRow(account: binding(for: account.id))
                }
                HStack {
                    TextField("New account name", text: $newAccount)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Claude")
            } footer: {
                Text("Connect Claude through the Anthropic API key or Claude Code (MCP). More providers will live here.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connectors")
    }

    private func add() {
        identity.addAccount(name: newAccount)
        newAccount = ""
    }

    private func binding(for id: UUID) -> Binding<Account> {
        Binding(
            get: { identity.accounts.first { $0.id == id } ?? Account(name: "") },
            set: { identity.updateAccount($0) }
        )
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
        .navigationTitle("Decks")
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

private struct AccountRow: View {
    @Environment(IdentityStore.self) private var identity
    @Binding var account: Account

    @State private var key = ""
    @State private var status = Status.idle
    @State private var registered = false

    private enum Status: Equatable {
        case idle, checking, ok, failed(String)
    }

    var body: some View {
        DisclosureGroup(account.name.isEmpty ? "Account" : account.name) {
            TextField("Name", text: $account.name)
            Picker("Mode", selection: $account.mode) {
                Text("Claude Code (MCP)").tag(AccountMode.login)
                Text("Anthropic API key").tag(AccountMode.apiKey)
            }
            TextField("Model", text: $account.model)

            if account.mode == .apiKey {
                SecureField("Anthropic API key", text: $key)
                HStack {
                    Button("Verify & save", action: verify)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || status == .checking)
                    statusLabel
                }
            } else {
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

            Button("Delete", role: .destructive) {
                identity.deleteAccount(account.id)
            }
        }
        .onAppear {
            key = identity.apiKey(for: account.id)
            registered = ClaudeCode.decksRegistered()
        }
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
            switch await AnthropicClient().validate(apiKey: trimmed) {
            case .success: status = .ok
            case let .failure(error): status = .failed(error.localizedDescription)
            }
        }
    }

    private func copyCommand() {
        let bin = ("~/.cargo/bin/decks-mcp" as NSString).expandingTildeInPath
        let command = "claude mcp add decks -- \(bin)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
