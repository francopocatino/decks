import AppKit
import SwiftUI

struct DailyView: View {
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
                    MarkdownView(text: store.daily(slug))
                        .padding(16)
                }
            } else {
                TextEditor(text: dailyBinding)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
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
                Label("Today", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)

            if DeckAssistant.hasBackend(for: slug, identity: identity) {
                Button(action: draftToday) {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Draft", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(working)
                .help("Draft today's entry with AI")
            }

            Spacer()

            if !store.daily(slug).isEmpty {
                Button(action: copyToday) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy today's entry to the clipboard")
            }

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
                let draft = try await DeckAssistant.run(system: system, user: context, slug: slug, identity: identity)
                store.addDailyLine(draft, to: slug)
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
