import SwiftUI

struct TodosView: View {
    @Environment(DecksStore.self) private var store
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
                Text(todo.text)
                    .strikethrough(todo.done, color: .secondary)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .onTapGesture(count: 2) { startEdit(todo) }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Edit") { startEdit(todo) }
            Button("Delete", role: .destructive) {
                store.deleteTodo(todo.id, in: slug)
            }
        }
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
