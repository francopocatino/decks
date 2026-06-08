import SwiftUI

struct DeckSettingsView: View {
    @Environment(IdentityStore.self) private var identity
    let deck: Deck
    var onClose: () -> Void

    @State private var profile = DeckProfile()
    @State private var newRepo = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("AI account") {
                    Picker("Account", selection: $profile.accountID) {
                        Text("None").tag(UUID?.none)
                        ForEach(identity.accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
                Section("Git") {
                    Picker("Provider", selection: $profile.gitProvider) {
                        ForEach(GitProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    TextField("Commit email", text: $profile.authorEmail)
                }
                Section("Repositories") {
                    ForEach(profile.repos, id: \.self) { repo in
                        Text(repo).font(.callout).foregroundStyle(.secondary)
                    }
                    .onDelete { profile.repos.remove(atOffsets: $0) }
                    HStack {
                        TextField("Repository path", text: $newRepo)
                            .onSubmit(addRepo)
                        Button("Add", action: addRepo)
                            .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onClose)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 440)
        .onAppear { profile = identity.profile(deck.slug) }
    }

    private func addRepo() {
        let trimmed = newRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.repos.append(trimmed)
        newRepo = ""
    }

    private func save() {
        identity.saveProfile(profile, for: deck.slug)
        onClose()
    }
}
