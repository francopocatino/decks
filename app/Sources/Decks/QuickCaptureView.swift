import SwiftUI

struct QuickCaptureView: View {
    @Environment(DecksStore.self) private var store
    @State private var slug: String?
    @State private var text = ""
    @State private var mode: CaptureMode = .todo

    private enum CaptureMode: String, CaseIterable, Identifiable {
        case todo, daily
        var id: String { rawValue }
        var label: String { self == .todo ? "To-do" : "Daily" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick capture").font(.headline)

            Picker("Deck", selection: $slug) {
                ForEach(store.visibleDecks) { deck in
                    Text(deck.name).tag(Optional(deck.slug))
                }
            }

            Picker("Kind", selection: $mode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(mode == .todo ? "Add a to-do…" : "Add to today…", text: $text, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)

            HStack {
                Spacer()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(slug == nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            if slug == nil || !store.visibleDecks.contains(where: { $0.slug == slug }) {
                slug = store.activeSlug ?? store.visibleDecks.first?.slug
            }
        }
    }

    private func add() {
        guard let slug, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch mode {
        case .todo: store.addTodo(text, to: slug)
        case .daily: store.addDailyLine(text, to: slug)
        }
        text = ""
    }
}
