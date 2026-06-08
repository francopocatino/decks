import SwiftUI

struct SettingsView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var newAccount = ""

    var body: some View {
        Form {
            Section("AI accounts") {
                if identity.accounts.isEmpty {
                    Text("No accounts yet. Add one and point decks at it; several decks can share the same account.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(identity.accounts) { account in
                    AccountRow(account: account)
                }
                HStack {
                    TextField("New account name", text: $newAccount)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
    }

    private func add() {
        identity.addAccount(name: newAccount)
        newAccount = ""
    }
}

private struct AccountRow: View {
    @Environment(IdentityStore.self) private var identity
    let account: Account
    @State private var draft: Account
    @State private var key = ""

    init(account: Account) {
        self.account = account
        _draft = State(initialValue: account)
    }

    var body: some View {
        DisclosureGroup(account.name.isEmpty ? "Account" : account.name) {
            TextField("Name", text: $draft.name)
            Picker("Mode", selection: $draft.mode) {
                ForEach(AccountMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            TextField("Model", text: $draft.model)
            if draft.mode == .apiKey {
                SecureField("Anthropic API key", text: $key)
            }
            HStack {
                Button("Save", action: save)
                Spacer()
                Button("Delete", role: .destructive) {
                    identity.deleteAccount(account.id)
                }
            }
        }
        .onAppear { key = identity.apiKey(for: account.id) }
    }

    private func save() {
        identity.updateAccount(draft)
        if draft.mode == .apiKey {
            identity.setAPIKey(key, for: draft.id)
        }
    }
}
