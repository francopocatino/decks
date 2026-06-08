import SwiftUI

struct NotesView: View {
    @Environment(DecksStore.self) private var store
    let slug: String

    var body: some View {
        TextEditor(text: notesBinding)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(16)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.notes(slug) },
            set: { store.setNotes($0, for: slug) }
        )
    }
}
