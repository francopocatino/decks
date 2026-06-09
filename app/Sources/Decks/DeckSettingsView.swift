import AppKit
import SwiftUI

struct DeckSettingsView: View {
    @Environment(IdentityStore.self) private var identity
    let deck: Deck
    var onClose: () -> Void

    @State private var profile = DeckProfile()

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
                Section {
                    ForEach(profile.folders, id: \.self) { folder in
                        Text(folder).font(.callout).foregroundStyle(.secondary)
                    }
                    .onDelete { profile.folders.remove(atOffsets: $0) }
                    Button(action: addFolder) {
                        Label("Add folder…", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("Everything under these folders belongs to this deck. The worklog scans them for git activity.")
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
        .frame(width: 480, height: 470)
        .onAppear { profile = identity.profile(deck.slug) }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url, !profile.folders.contains(url.path) {
            profile.folders.append(url.path)
        }
    }

    private func save() {
        identity.saveProfile(profile, for: deck.slug)
        onClose()
    }
}
