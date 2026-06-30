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
            MarkdownEditor(text: notesBinding, controller: editor, accent: accent)
        }
        .alert("Couldn't polish", isPresented: aiErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if DeckAssistant.hasBackend(for: slug, parent: parent, identity: identity), !store.notes(slug).isEmpty {
                Button(action: polish) {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(working)
                .help("Rewrite these notes cleaner with AI")

                if showToolbar {
                    Divider().frame(height: 14)
                }
            }
            // A horizontal scroll keeps the format buttons from overflowing and
            // overlapping the trailing control when the pane is narrow.
            if showToolbar {
                ScrollView(.horizontal, showsIndicators: false) {
                    MarkdownFormatButtons(controller: editor)
                }
                .frame(height: 22)
            } else {
                Spacer()
            }
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

    private var accent: NSColor {
        store.deck(slug).map { store.accentNSColor(for: $0) } ?? .controlAccentColor
    }

    private var parent: String? { store.deck(slug)?.parent }

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
                let reply = try await DeckAssistant.run(system: system, user: store.notes(slug), slug: slug, parent: parent, identity: identity)
                if reply.truncated {
                    aiError = "These notes are too long to polish without cutting them off, so they were left unchanged."
                } else {
                    store.setNotes(reply.text, for: slug)
                }
            } catch {
                aiError = error.localizedDescription
            }
            working = false
        }
    }
}
