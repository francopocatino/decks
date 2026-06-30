import SwiftUI

// A single command the palette can run, surfaced alongside deck navigation.
struct CommandAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let run: () -> Void
}

// Spotlight-style jump bar: fuzzy-search every deck plus a set of actions,
// keyboard-driven (↑/↓ to move, ⏎ to run, ⎋ to close). Lives as an overlay in
// the main window, opened with ⌘K.
struct CommandPalette: View {
    @Environment(DecksStore.self) private var store
    @Binding var isPresented: Bool
    let actions: [CommandAction]

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to a deck or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { runSelection(); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
                    .onChange(of: query) { _, _ in selection = 0 }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, index: index).id(index)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { _, value in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        .onAppear { focused = true }
    }

    private enum Item: Identifiable {
        case deck(Deck)
        case action(CommandAction)

        var id: String {
            switch self {
            case let .deck(deck): "deck-\(deck.slug)"
            case let .action(action): "action-\(action.id)"
            }
        }

        var text: String {
            switch self {
            case let .deck(deck): deck.name
            case let .action(action): action.title
            }
        }
    }

    private var results: [Item] {
        let all = store.visibleDecks.map(Item.deck) + actions.map(Item.action)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all
            .compactMap { item in Self.score(query: q, text: item.text).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    @ViewBuilder
    private func row(_ item: Item, index: Int) -> some View {
        let active = index == selection
        HStack(spacing: 10) {
            switch item {
            case let .deck(deck):
                DeckIcon(deck: deck, accent: store.accent(for: deck))
                Text(deck.name)
                Spacer()
                let open = store.openTodoCount(deck.slug)
                if open > 0 {
                    Text("\(open)").font(.caption).foregroundStyle(.secondary)
                }
            case let .action(action):
                Image(systemName: action.symbol)
                    .frame(width: 16)
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(action.title)
                if let subtitle = action.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { perform(item) }
        .onHover { if $0 { selection = index } }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func runSelection() {
        guard results.indices.contains(selection) else { return }
        perform(results[selection])
    }

    private func perform(_ item: Item) {
        isPresented = false
        switch item {
        case let .deck(deck): store.select(deck.slug)
        case let .action(action): action.run()
        }
    }

    // Prefix beats substring beats subsequence; shorter matches rank higher.
    private static func score(query: String, text: String) -> Int? {
        let q = query.lowercased()
        let t = text.lowercased()
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 800 - t.count }
        if t.contains(q) { return 500 - t.count }
        return isSubsequence(q, of: t) ? 200 - t.count : nil
    }

    private static func isSubsequence(_ query: String, of text: String) -> Bool {
        var iterator = text.makeIterator()
        for character in query {
            var matched = false
            while let next = iterator.next() {
                if next == character { matched = true; break }
            }
            if !matched { return false }
        }
        return true
    }
}
