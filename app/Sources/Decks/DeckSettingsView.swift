import AppKit
import SwiftUI

struct DeckSettingsView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(DecksStore.self) private var store
    let deck: Deck
    var onClose: () -> Void

    @State private var profile = DeckProfile()
    @State private var parentSlug: String?

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
                Section {
                    ZStack(alignment: .topLeading) {
                        if profile.instructions.isEmpty {
                            Text("e.g. Write the daily in English as Yesterday / Today / Blockers bullets.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $profile.instructions)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 96)
                    }
                } header: {
                    Text("AI instructions")
                } footer: {
                    Text("How AI should write for this deck — language, daily format, tone. Used by Ask, and by Claude over the MCP server (it reads these from show_deck).")
                }
                Section {
                    if store.canHaveParent(deck.slug) {
                        Picker("Parent deck", selection: $parentSlug) {
                            Text("None").tag(String?.none)
                            ForEach(store.parentCandidates(for: deck.slug)) { candidate in
                                Text(candidate.name).tag(Optional(candidate.slug))
                            }
                        }
                    } else {
                        Text("This deck has sub-decks, so it can't become one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Parent")
                } footer: {
                    Text("A sub-deck inherits its parent's AI account, commit email, git provider and instructions when its own are empty, and sees the parent's links.")
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
        .frame(width: 480, height: 560)
        .onAppear {
            profile = identity.profile(deck.slug)
            parentSlug = deck.parent
        }
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
        store.setParent(deck.slug, to: parentSlug)
        onClose()
    }
}
