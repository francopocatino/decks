import SwiftUI

struct NotesView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    let slug: String
    @State private var preview = false
    @State private var working = false
    @State private var aiError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .alert("Couldn't polish", isPresented: aiErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if DeckAssistant.connector(for: slug, identity: identity) != nil, !store.notes(slug).isEmpty {
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
            }
            Spacer()
            Picker("", selection: $preview) {
                Image(systemName: "pencil").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
