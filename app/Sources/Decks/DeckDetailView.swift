import SwiftUI

struct DeckDetailView: View {
    let deck: Deck
    @Binding var section: DeckSection

    var body: some View {
        content
            .navigationTitle(deck.name)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $section) {
                        ForEach(DeckSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
}
