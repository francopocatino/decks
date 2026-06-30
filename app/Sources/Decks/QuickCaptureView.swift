import SwiftUI

struct QuickCaptureView: View {
    @Environment(DecksStore.self) private var store
    @Environment(PomodoroEngine.self) private var pomodoro
    var focusOnAppear = false
    var onDone: (() -> Void)?
    @State private var slug: String?
    @State private var text = ""
    @State private var mode: CaptureMode = .todo
    @FocusState private var fieldFocused: Bool

    private enum CaptureMode: String, CaseIterable, Identifiable {
        case todo, daily
        var id: String { rawValue }
        var label: String { self == .todo ? "To-do" : "Daily" }
        var symbol: String { self == .todo ? "checklist" : "calendar" }
        var placeholder: String { self == .todo ? "Add a to-do…" : "Add to today's daily…" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .contentTransition(.symbolEffect(.replace))
                TextField(mode.placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(1 ... 4)
                    .focused($fieldFocused)
                    .onSubmit(add)
                if !trimmed.isEmpty {
                    Button(action: add) {
                        Image(systemName: "return")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add (Return)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Menu {
                    ForEach(store.visibleDecks) { deck in
                        Button {
                            slug = deck.slug
                        } label: {
                            Label {
                                Text(deck.name)
                            } icon: {
                                DeckIcon(deck: deck, accent: store.accent(for: deck), indented: true)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let deck = selectedDeck {
                            DeckIcon(deck: deck, accent: store.accent(for: deck))
                            Text(deck.name)
                        } else {
                            Text("Choose a deck")
                        }
                    }
                    .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            focusStrip
        }
        .frame(width: 400)
        .tint(selectedDeck.flatMap { store.accentTint(for: $0) } ?? .accentColor)
        .onAppear {
            if slug == nil || !store.visibleDecks.contains(where: { $0.slug == slug }) {
                slug = store.activeSlug ?? store.visibleDecks.first?.slug
            }
            if focusOnAppear {
                Task { fieldFocused = true }
            }
        }
    }

    private var focusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(.secondary)
            if pomodoro.phase == .idle {
                Text("Focus").foregroundStyle(.secondary)
            } else {
                Text(pomodoro.phase.title).foregroundStyle(.secondary)
                Text(pomodoro.timeString).monospacedDigit()
            }
            Spacer()
            Button { pomodoro.toggle() } label: {
                Image(systemName: pomodoro.running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(pomodoro.running ? "Pause focus" : "Start focus")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private var selectedDeck: Deck? {
        slug.flatMap { store.deck($0) }
    }

    private func add() {
        guard let slug, !trimmed.isEmpty else { return }
        switch mode {
        case .todo: store.addTodo(text, to: slug)
        case .daily: store.addDailyLine(text, to: slug)
        }
        text = ""
        onDone?()
    }
}
