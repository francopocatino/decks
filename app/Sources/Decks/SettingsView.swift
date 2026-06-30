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
    @AppStorage(Pref.captureHotkey) private var captureHotkey: HotkeyOption = .ctrlOptSpace
    @AppStorage(Pref.pomodoroHotkey) private var pomodoroHotkey: HotkeyOption = .ctrlOptP
    @AppStorage(PomodoroEngine.workKey) private var pomodoroWork = 25
    @AppStorage(PomodoroEngine.shortKey) private var pomodoroShort = 5
    @AppStorage(PomodoroEngine.longKey) private var pomodoroLong = 15
    @AppStorage(Pref.meetingAlerts) private var meetingAlerts = false
    @AppStorage(Pref.meetingAlertLead) private var meetingAlertLead = 2
    @AppStorage(Pref.dueAlerts) private var dueAlerts = false
    @AppStorage(Pref.icloudMirror) private var icloudMirror = false
    @State private var notificationsDenied = false
    @Environment(UpdateChecker.self) private var updates
    @Environment(HotkeyManager.self) private var hotkey

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
            Section {
                Picker("Quick capture hotkey", selection: $captureHotkey) {
                    ForEach(HotkeyOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                if hotkey.registrationFailed {
                    Text("This shortcut couldn't be registered — another app may already be using it. Pick a different one.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Quick capture")
            } footer: {
                Text("Opens the capture panel from anywhere, even when Decks is in the background.")
            }
            Section {
                Picker("Start/pause hotkey", selection: $pomodoroHotkey) {
                    ForEach(HotkeyOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Stepper("Focus: \(pomodoroWork) min", value: $pomodoroWork, in: 5 ... 90, step: 5)
                Stepper("Short break: \(pomodoroShort) min", value: $pomodoroShort, in: 1 ... 30, step: 1)
                Stepper("Long break: \(pomodoroLong) min", value: $pomodoroLong, in: 5 ... 45, step: 5)
            } header: {
                Text("Focus timer")
            } footer: {
                Text("A Pomodoro focus timer in the menu bar and as a floating window. The hotkey starts or pauses it from anywhere; a long break follows every four focus sessions.")
            }
            Section {
                Toggle("Meeting alerts", isOn: alertsBinding($meetingAlerts))
                if meetingAlerts {
                    Picker("Warn me", selection: $meetingAlertLead) {
                        ForEach([1, 2, 5, 10], id: \.self) { minutes in
                            Text("\(minutes) min before").tag(minutes)
                        }
                    }
                }
                Toggle("To-do due alerts", isOn: alertsBinding($dueAlerts))
                if notificationsDenied {
                    Text("Notifications are off for Decks. Allow them in System Settings → Notifications, then try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Meeting alerts cover every deck's calendars and offer a Join button when the event has a meeting link. Due alerts fire when an open to-do reaches its due date.")
            }
            Section {
                Toggle("Mirror decks to iCloud Drive", isOn: $icloudMirror)
                    .disabled(!CloudMirrorEngine.isAvailable)
            } header: {
                Text("iCloud")
            } footer: {
                Text(CloudMirrorEngine.isAvailable
                    ? "Writes a read-only markdown digest per deck to iCloud Drive → Decks, readable from Files on iPhone. One-way: edits there are overwritten."
                    : "iCloud Drive is not available on this Mac.")
            }
            Section {
                LabeledContent("Current version", value: updates.currentVersion)
                if let update = updates.update {
                    HStack {
                        Text("Version \(update.version) is available")
                        Spacer()
                        Button {
                            Task { await updates.install() }
                        } label: {
                            if updates.installing {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Install & relaunch")
                            }
                        }
                        .disabled(updates.installing)
                    }
                    if let error = updates.installError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } else {
                    Button("Check for updates") {
                        Task { await updates.check() }
                    }
                }
            } header: {
                Text("Software update")
            } footer: {
                Text("Updates download and replace the app, then relaunch. Calendar access may need re-granting after an update.")
            }
        }
        .formStyle(.grouped)
    }

    private func alertsBinding(_ storage: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { storage.wrappedValue },
            set: { isOn in
                guard isOn else {
                    storage.wrappedValue = false
                    return
                }
                Task {
                    let granted = await NotificationScheduler.requestAccess()
                    storage.wrappedValue = granted
                    notificationsDenied = !granted
                }
            }
        )
    }
}

struct ConnectorsView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var draft: ConnectorDraft?

    var body: some View {
        Form {
            connectorSection("AI", footer: "Claude and OpenAI power Ask and the MCP server.", kinds: [.claude, .openai])
            connectorSection("Git", footer: "Tokens that enrich the worklog with your PRs and issues.", kinds: [.github, .gitlab])
        }
        .formStyle(.grouped)
        .sheet(item: $draft) { item in
            ConnectorEditor(draft: item) { draft = nil }
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
                    draft = ConnectorDraft(account: account, isNew: false)
                } onDelete: {
                    identity.deleteAccount(account.id)
                }
            }
            Menu {
                ForEach(kinds) { kind in
                    Button {
                        draft = ConnectorDraft(account: Account(name: "", kind: kind), isNew: true)
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
}

struct ConnectorDraft: Identifiable {
    var account: Account
    var isNew: Bool
    var id: UUID { account.id }
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
        Label {
            Text(deck.name)
        } icon: {
            DeckIcon(deck: deck, accent: store.accent(for: deck))
        }
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
    @State private var account: Account
    private let isNew: Bool
    var onClose: () -> Void

    @State private var key = ""
    @State private var status = Status.idle
    @State private var registered = false

    init(draft: ConnectorDraft, onClose: @escaping () -> Void) {
        _account = State(initialValue: draft.account)
        isNew = draft.isNew
        self.onClose = onClose
    }

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
                            Button("Verify", action: verify)
                                .disabled(!keyFormatValid || status == .checking)
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
                if !isNew {
                    Button("Delete", role: .destructive) {
                        identity.deleteAccount(account.id)
                        onClose()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(12)
        }
        .frame(width: 420, height: 360)
        .onAppear {
            if !isNew { key = identity.apiKey(for: account.id) }
            registered = ClaudeCode.decksRegistered()
        }
    }

    private var keyTrimmed: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var keyFormatValid: Bool {
        switch account.kind {
        case .claude: keyTrimmed.hasPrefix("sk-ant-")
        case .openai: keyTrimmed.hasPrefix("sk-")
        case .github: keyTrimmed.hasPrefix("ghp_") || keyTrimmed.hasPrefix("github_pat_")
        case .gitlab: keyTrimmed.hasPrefix("glpat-")
        }
    }

    private var isValid: Bool {
        guard !account.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return needsKey ? keyFormatValid : true
    }

    private func save() {
        identity.upsertAccount(account)
        if needsKey { identity.setAPIKey(keyTrimmed, for: account.id) }
        onClose()
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
        let trimmed = keyTrimmed
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
