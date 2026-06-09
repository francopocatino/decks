import SwiftUI

struct NotesView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var preview = false

    var body: some View {
        VStack(spacing: 0) {
            MarkdownToggle(preview: $preview)
            if preview {
                ScrollView {
                    MarkdownView(text: store.notes(slug))
                        .padding(16)
                }
            } else {
                TextEditor(text: notesBinding)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.notes(slug) },
            set: { store.setNotes($0, for: slug) }
        )
    }
}
