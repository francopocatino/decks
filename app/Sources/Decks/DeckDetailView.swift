import SwiftUI

struct DeckDetailView: View {
    let deck: Deck
    @Binding var section: DeckSection
    @State private var showingAsk = false

    var body: some View {
        content
            .navigationTitle(deck.name)
            .background { sectionShortcuts }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section) {
                        ForEach(DeckSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAsk = true } label: {
                        Label("Ask", systemImage: "sparkles")
                    }
                }
            }
            .sheet(isPresented: $showingAsk) {
                AskView(deck: deck) { showingAsk = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .daily: DailyView(slug: deck.slug)
        case .todos: TodosView(slug: deck.slug)
        case .notes: NotesView(slug: deck.slug)
        case .links: LinksView(slug: deck.slug)
        }
    }

    private var sectionShortcuts: some View {
        ForEach(Array(DeckSection.allCases.enumerated()), id: \.element.id) { index, value in
            Button("") { section = value }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .hidden()
        }
    }
}
