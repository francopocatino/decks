import SwiftUI

struct NotesView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    let slug: String
    @State private var working = false
    @State private var aiError: String?
    @State private var editor = MarkdownEditorController()
    @AppStorage(Pref.markdownToolbar) private var showToolbar = true

    var body: some View {
        VStack(spacing: 0) {
            header
            MarkdownEditor(text: notesBinding, controller: editor)
        }
        .alert("Couldn't polish", isPresented: aiErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if DeckAssistant.hasBackend(for: slug, identity: identity), !store.notes(slug).isEmpty {
                Button(action: polish) {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Polish", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(working)
                .help("Rewrite these notes cleaner with AI")

                if showToolbar {
                    Divider().frame(height: 14)
                }
            }
            if showToolbar {
                MarkdownFormatButtons(controller: editor)
            }
            Spacer()
            Button {
                showToolbar.toggle()
            } label: {
                Image(systemName: "textformat")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(showToolbar ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(showToolbar ? "Hide formatting buttons" : "Show formatting buttons")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.notes(slug) },
            set: { store.setNotes($0, for: slug) }
        )
    }

    private var aiErrorBinding: Binding<Bool> {
        Binding(get: { aiError != nil }, set: { if !$0 { aiError = nil } })
    }

    private func polish() {
        let system = "Rewrite these notes in clean markdown. Keep every piece of information; only fix grammar, structure and formatting. Output only the rewritten notes, no preamble."
        working = true
        aiError = nil
        Task {
            do {
                let result = try await DeckAssistant.run(system: system, user: store.notes(slug), slug: slug, identity: identity)
                store.setNotes(result, for: slug)
            } catch {
                aiError = error.localizedDescription
            }
            working = false
        }
    }
}
