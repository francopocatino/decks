import SwiftUI

struct RootView: View {
    @Environment(DecksStore.self) private var store
    @State private var section: DeckSection = .daily
    @State private var showingNewDeck = false
    @State private var newDeckName = ""

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                Section("Decks") {
                    ForEach(store.decks) { deck in
                        Label(deck.name, systemImage: "rectangle.stack")
                            .tag(deck.slug)
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
            NewDeckSheet(name: $newDeckName, onCreate: create, onCancel: dismissSheet)
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { store.activeSlug },
            set: { if let slug = $0 { store.select(slug) } }
        )
    }

    private func create() {
        store.createDeck(name: newDeckName)
        dismissSheet()
    }

    private func dismissSheet() {
        newDeckName = ""
        showingNewDeck = false
    }
}

private struct NewDeckSheet: View {
    @Binding var name: String
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New deck").font(.headline)
            TextField("Company or project", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onCreate)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
