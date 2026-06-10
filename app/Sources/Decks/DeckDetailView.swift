import SwiftUI

struct DeckDetailView: View {
    @Environment(DecksStore.self) private var store
    let deck: Deck
    @State private var layout = DeckLayout()

    private func leaves(_ node: PaneNode) -> [DeckSection] {
        switch node {
        case let .leaf(section): [section]
        case let .split(_, _, first, second): leaves(first) + leaves(second)
        }
    }

    var body: some View {
        let sections = leaves(layout.root)
        return PaneTreeView(
            slug: deck.slug,
            node: layout.root,
            used: Set(sections),
            canSplit: sections.count < 4
        ) { newRoot in
            layout.root = newRoot
            store.setLayout(layout, for: deck.slug)
        }
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Reset to single pane", action: resetLayout)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Layout")
            }
        }
        .onAppear { layout = store.layout(deck.slug) }
    }

    private func resetLayout() {
        layout.root = .leaf(.daily)
        store.setLayout(layout, for: deck.slug)
    }
}
