import AppKit
import SwiftUI

struct RootView: View {
    @Environment(DecksStore.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @Environment(IdentityStore.self) private var identity
    @Environment(ChatStore.self) private var chat
    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var newDeckParent: String?
    @State private var renaming: Deck?
    @State private var renameText = ""
    @State private var pendingDelete: Deck?
    @State private var settingsDeck: Deck?

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                Section("Decks") {
                    ForEach(store.topLevelVisibleDecks()) { deck in
                        let children = store.visibleChildren(of: deck.slug)
                        if children.isEmpty {
                            deckRow(deck)
                        } else {
                            DisclosureGroup {
                                ForEach(children) { child in
                                    deckRow(child)
                                }
                                .onMove { store.moveDecks(parent: deck.slug, fromOffsets: $0, toOffset: $1) }
                            } label: {
                                deckRow(deck)
                            }
                        }
                    }
                    .onMove { store.moveDecks(parent: nil, fromOffsets: $0, toOffset: $1) }
                }
                if !store.archivedDecks.isEmpty {
                    Section("Archived") {
                        ForEach(store.archivedDecks) { deck in
                            deckRow(deck)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        startNewDeck(parent: nil)
                    } label: {
                        Label("New deck", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n")
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        } detail: {
            if let deck = store.activeDeck {
                DeckDetailView(deck: deck)
                    .id(deck.slug)
            } else {
                ContentUnavailableView(
                    "No deck yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Create one for each project or context you switch between.")
                )
            }
        }
        .sheet(isPresented: $showingNewDeck) {
            DeckNameSheet(
                title: newDeckParent == nil ? "New deck" : "New sub-deck",
                name: $newDeckName,
                confirmLabel: "Create"
            ) {
                store.createDeck(name: newDeckName, parent: newDeckParent)
                newDeckName = ""
                newDeckParent = nil
                showingNewDeck = false
            } onCancel: {
                newDeckName = ""
                newDeckParent = nil
                showingNewDeck = false
            }
        }
        .sheet(item: $renaming) { deck in
            DeckNameSheet(title: "Rename deck", name: $renameText, confirmLabel: "Rename") {
                store.renameDeck(deck.slug, to: renameText)
                renaming = nil
            } onCancel: {
                renaming = nil
            }
        }
        .sheet(item: $settingsDeck) { deck in
            DeckSettingsView(deck: deck) { settingsDeck = nil }
                .environment(identity)
        }
        .confirmationDialog("Delete this deck?", isPresented: deleteDialog, presenting: pendingDelete) { deck in
            Button("Delete \(deck.name)", role: .destructive) {
                store.deleteDeck(deck.slug)
                chat.forget(deck.slug)
                identity.forgetProfile(deck.slug)
            }
        } message: { _ in
            Text("This removes the deck and all its notes from disk. This cannot be undone.")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                store.reloadIfChanged()
            }
        }
        .safeAreaInset(edge: .top) {
            if let update = updates.update {
                UpdateBanner(update: update)
            }
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        Label(deck.name, systemImage: deck.isArchived ? "archivebox" : "rectangle.stack")
            .badge(badge(for: deck))
            .tag(deck.slug)
            .contextMenu {
                Button("Rename") { startRename(deck) }
                Button("Settings…") { settingsDeck = deck }
                if deck.parent == nil, !deck.isArchived {
                    Button("Add sub-deck") { startNewDeck(parent: deck.slug) }
                }
                if deck.isArchived {
                    Button("Unarchive") { store.setArchived(deck.slug, false) }
                } else {
                    Button("Archive") { store.setArchived(deck.slug, true) }
                }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = deck }
            }
    }

    private func startNewDeck(parent: String?) {
        newDeckName = ""
        newDeckParent = parent
        showingNewDeck = true
    }

    private func badge(for deck: Deck) -> Text? {
        let count = store.openTodoCount(deck.slug)
        return count > 0 ? Text("\(count)") : nil
    }

    private func startRename(_ deck: Deck) {
        renameText = deck.name
        renaming = deck
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { store.activeSlug },
            set: { if let slug = $0 { store.select(slug) } }
        )
    }

    private var deleteDialog: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

private struct UpdateBanner: View {
    let update: UpdateChecker.Update

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text("Version \(update.version) is available.")
            Spacer()
            Button("View update") {
                NSWorkspace.shared.open(update.url)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct DeckNameSheet: View {
    let title: String
    @Binding var name: String
    let confirmLabel: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Project or context", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onConfirm)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button(confirmLabel, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
