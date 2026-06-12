import SwiftUI

struct TodosView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    let slug: String
    @State private var draft = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if store.todos(slug).isEmpty {
                ContentUnavailableView(
                    "No to-dos",
                    systemImage: "checklist",
                    description: Text("Add things to do or review for this deck.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.todos(slug)) { todo in
                        row(todo)
                    }
                }
                .listStyle(.inset)
            }

            composer
        }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            Button {
                store.toggleTodo(todo.id, in: slug)
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.done ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            if editingID == todo.id {
                TextField("To-do", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($editorFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                    .onChange(of: editorFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(todo.text)
                        .strikethrough(todo.done, color: .secondary)
                        .foregroundStyle(todo.done ? .secondary : .primary)
                    if let due = todo.due {
                        Text(dueLabel(due))
                            .font(.caption)
                            .foregroundStyle(!todo.done && due < Date() ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    }
                }
                .onTapGesture(count: 2) { startEdit(todo) }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Edit") { startEdit(todo) }
            Menu("Due") {
                Button("Today 18:00") { store.setDue(dueDate(daysAhead: 0, hour: 18), for: todo.id, in: slug) }
                Button("Tomorrow 09:00") { store.setDue(dueDate(daysAhead: 1, hour: 9), for: todo.id, in: slug) }
                Button("Next week 09:00") { store.setDue(dueDate(daysAhead: 7, hour: 9), for: todo.id, in: slug) }
                if todo.due != nil {
                    Divider()
                    Button("Clear") { store.setDue(nil, for: todo.id, in: slug) }
                }
            }
            Menu("Block time") {
                Button("Next half hour, 1 h") { blockTime(todo, start: nextHalfHour(), hours: 1) }
                Button("Today 16:00, 1 h") { blockTime(todo, start: dueDate(daysAhead: 0, hour: 16), hours: 1) }
                Button("Tomorrow 09:00, 1 h") { blockTime(todo, start: dueDate(daysAhead: 1, hour: 9), hours: 1) }
            }
            Button("Delete", role: .destructive) {
                store.deleteTodo(todo.id, in: slug)
            }
        }
    }

    private func nextHalfHour(from date: Date = Date()) -> Date {
        let interval: TimeInterval = 1800
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval + interval)
    }

    private func blockTime(_ todo: Todo, start: Date, hours: Double) {
        let deckName = store.deck(slug)?.name ?? slug
        let sources = identity.effectiveCalendarSources(for: slug, parent: store.deck(slug)?.parent)
        Task {
            await CalendarService.createTimeBlock(
                title: todo.text,
                start: start,
                duration: hours * 3600,
                sources: sources,
                note: "Decks · \(deckName)"
            )
        }
    }

    private func dueDate(daysAhead: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    private func dueLabel(_ due: Date) -> String {
        if Calendar.current.isDateInToday(due) {
            return "Due \(due.formatted(date: .omitted, time: .shortened))"
        }
        return "Due \(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(due.formatted(date: .omitted, time: .shortened))"
    }

    private func startEdit(_ todo: Todo) {
        editingID = todo.id
        editText = todo.text
        editorFocused = true
    }

    private func commitEdit() {
        guard let id = editingID else { return }
        store.editTodo(id, text: editText, in: slug)
        editingID = nil
    }

    private func cancelEdit() {
        editingID = nil
    }

    private var composer: some View {
        HStack {
            TextField("Add a to-do", text: $draft)
                .textFieldStyle(.plain)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: "return")
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func add() {
        store.addTodo(draft, to: slug)
        draft = ""
    }
}
