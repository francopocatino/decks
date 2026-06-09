import SwiftUI

struct DeckDetailView: View {
    @Environment(DecksStore.self) private var store
    let deck: Deck
    @State private var layout = DeckLayout()
    @State private var showingAsk = false

    var body: some View {
        panes
            .navigationTitle(deck.name)
            .background { sectionShortcuts }
            .toolbar {
                if layout.mode == .single {
                    ToolbarItem(placement: .principal) {
                        Picker("Section", selection: slotBinding(0)) {
                            ForEach(DeckSection.allCases) { section in
                                Text(section.title).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Layout", selection: layoutModeBinding) {
                            ForEach(LayoutMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: layout.mode.symbol)
                    }
                    .help("Pane layout")
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
        PaneView(slug: deck.slug, section: slotBinding(index), showsHeader: layout.mode != .single)
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
    var showsHeader: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
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
            }
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
        case .meetings: MeetingsView(slug: slug)
        }
    }
}
