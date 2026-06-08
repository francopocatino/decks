import SwiftUI

struct RootView: View {
    @Environment(DecksStore.self) private var store
    @State private var section: DeckSection = .daily
    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var renaming: Deck?
    @State private var renameText = ""
    @State private var pendingDelete: Deck?

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                Section("Decks") {
                    ForEach(store.visibleDecks) { deck in
                        deckRow(deck)
                    }
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
                Button {
                    showingNewDeck = true
                } label: {
                    Label("New deck", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        } detail: {
            if let deck = store.activeDeck {
                DeckDetailView(deck: deck, section: $section)
            } else {
                ContentUnavailableView(
                    "No deck yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Create one for each company or project you keep notes for.")
                )
            }
        }
        .sheet(isPresented: $showingNewDeck) {
            DeckNameSheet(title: "New deck", name: $newDeckName, confirmLabel: "Create") {
                store.createDeck(name: newDeckName)
                newDeckName = ""
                showingNewDeck = false
            } onCancel: {
                newDeckName = ""
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
        .confirmationDialog("Delete this deck?", isPresented: deleteDialog, presenting: pendingDelete) { deck in
            Button("Delete \(deck.name)", role: .destructive) {
                store.deleteDeck(deck.slug)
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
    }

    private func deckRow(_ deck: Deck) -> some View {
        Label(deck.name, systemImage: deck.isArchived ? "archivebox" : "rectangle.stack")
            .tag(deck.slug)
            .contextMenu {
                Button("Rename") { startRename(deck) }
                if deck.isArchived {
                    Button("Unarchive") { store.setArchived(deck.slug, false) }
                } else {
                    Button("Archive") { store.setArchived(deck.slug, true) }
                }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = deck }
            }
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

private struct DeckNameSheet: View {
    let title: String
    @Binding var name: String
    let confirmLabel: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Company or project", text: $name)
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
