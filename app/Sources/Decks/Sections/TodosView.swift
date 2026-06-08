import SwiftUI

struct TodosView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.todos(slug)) { todo in
                    row(todo)
                }
            }
            .listStyle(.inset)

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

            Text(todo.text)
                .strikethrough(todo.done, color: .secondary)
                .foregroundStyle(todo.done ? .secondary : .primary)

            Spacer()
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Delete", role: .destructive) {
                store.deleteTodo(todo.id, in: slug)
            }
        }
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
