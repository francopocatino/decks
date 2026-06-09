import SwiftUI

struct DeckDetailView: View {
    @Environment(DecksStore.self) private var store
    let deck: Deck
    @State private var layout = DeckLayout()
    @State private var showingAsk = false
    @State private var showingSettings = false

    var body: some View {
        panes
            .navigationTitle(deck.name)
            .background { sectionShortcuts }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Layout", selection: layoutModeBinding) {
                        ForEach(LayoutMode.allCases) { mode in
                            Image(systemName: mode.symbol)
                                .help(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAsk = true } label: {
                        Label("Ask", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Label("Deck settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingAsk) {
                AskView(deck: deck) { showingAsk = false }
            }
            .sheet(isPresented: $showingSettings) {
                DeckSettingsView(deck: deck) { showingSettings = false }
            }
            .onAppear { layout = store.layout(deck.slug) }
    }

    @ViewBuilder
    private var panes: some View {
        switch layout.mode {
        case .single:
            pane(0)
        case .columns:
            HSplitView {
                pane(0)
                pane(1)
            }
        case .stack:
            HSplitView {
                VSplitView {
                    pane(0)
                    pane(1)
                }
                pane(2)
            }
        }
    }

    private func pane(_ index: Int) -> some View {
        PaneView(slug: deck.slug, section: slotBinding(index))
    }

    private func slotBinding(_ index: Int) -> Binding<DeckSection> {
        Binding(
            get: { layout.slots[index] },
            set: {
                layout.slots[index] = $0
                store.setLayout(layout, for: deck.slug)
            }
        )
    }

    private var layoutModeBinding: Binding<LayoutMode> {
        Binding(
            get: { layout.mode },
            set: {
                layout.mode = $0
                store.setLayout(layout, for: deck.slug)
            }
        )
    }

    private var sectionShortcuts: some View {
        ForEach(Array(DeckSection.allCases.enumerated()), id: \.element.id) { index, value in
            Button("") { slotBinding(0).wrappedValue = value }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                .hidden()
        }
    }
}

private struct PaneView: View {
    let slug: String
    @Binding var section: DeckSection

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(DeckSection.allCases) { option in
                        Button { section = option } label: {
                            Label(option.title, systemImage: option.symbol)
                        }
                    }
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(.headline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
        }
        .frame(minWidth: 240, minHeight: 180)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .daily: DailyView(slug: slug)
        case .todos: TodosView(slug: slug)
        case .notes: NotesView(slug: slug)
        case .links: LinksView(slug: slug)
        }
    }
}
