import AppKit
import SwiftUI

struct DailyView: View {
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
            MarkdownEditor(text: dailyBinding, controller: editor, accent: accent)
        }
        .alert("Couldn't draft", isPresented: aiErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                store.appendDailyEntry(to: slug)
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Start today's entry")

            if DeckAssistant.hasBackend(for: slug, parent: parent, identity: identity) {
                Button(action: draftToday) {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Draft", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(working)
                .help("Draft today's entry with AI from open to-dos and notes")
            }

            if showToolbar {
                Divider().frame(height: 14)
                MarkdownFormatButtons(controller: editor)
            }

            Spacer()

            if !store.daily(slug).isEmpty {
                Button(action: copyToday) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy today's entry to the clipboard")
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

    private var dailyBinding: Binding<String> {
        Binding(
            get: { store.daily(slug) },
            set: { store.setDaily($0, for: slug) }
        )
    }

    private var aiErrorBinding: Binding<Bool> {
        Binding(get: { aiError != nil }, set: { if !$0 { aiError = nil } })
    }

    private func draftToday() {
        let todos = store.todos(slug)
            .filter { !$0.done }
            .map { "- \($0.text)" }
            .joined(separator: "\n")
        let notes = store.notes(slug)
        let context = """
        Open to-dos:
        \(todos.isEmpty ? "(none)" : todos)

        Notes:
        \(notes.isEmpty ? "(none)" : notes)
        """
        let system = "Draft today's standup daily entry for this workspace as concise markdown bullets (in progress, next, blockers). Output only the entry, no preamble."
        working = true
        aiError = nil
        Task {
            do {
                let reply = try await DeckAssistant.run(system: system, user: context, slug: slug, parent: parent, identity: identity)
                store.addDailyLine(reply.text, to: slug)
            } catch {
                aiError = error.localizedDescription
            }
            working = false
        }
    }

    private func copyToday() {
        let daily = store.daily(slug)
        let header = "## \(DecksStore.dailyDate())"
        let block: String
        if daily.hasPrefix(header) {
            let afterHeader = daily.index(daily.startIndex, offsetBy: header.count)
            if let next = daily.range(of: "\n## ", range: afterHeader ..< daily.endIndex) {
                block = String(daily[..<next.lowerBound])
            } else {
                block = daily
            }
        } else {
            block = daily
        }
        let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
