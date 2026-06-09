import SwiftUI

struct AskView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    @Environment(ChatStore.self) private var chat
    let deck: Deck
    var onClose: () -> Void

    @State private var draft = ""
    @State private var sending = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let account, account.mode == .apiKey {
                thread
                composer
            } else {
                ContentUnavailableView(
                    "No API-key account",
                    systemImage: "key",
                    description: Text("Give this deck an account in API-key mode (Settings…) to chat here. Login-mode decks use Claude Code through the MCP server.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 560, height: 560)
    }

    private var account: Account? {
        identity.accounts.first { $0.id == identity.profile(deck.slug).accountID }
    }

    private var header: some View {
        HStack {
            Text("Ask \(deck.name)").font(.headline)
            Spacer()
            Button("Clear") { chat.clear(deck.slug) }
                .disabled(chat.messages(deck.slug).isEmpty)
            Button("Done", action: onClose)
        }
        .padding(12)
    }

    private var thread: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(chat.messages(deck.slug)) { message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.role == "user" ? "You" : deck.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if message.role == "assistant" {
                            MarkdownView(text: message.text)
                        } else {
                            Text(message.text).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let errorText {
                    Text(errorText).font(.callout).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom) {
            TextField("Ask about this deck…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .onSubmit(send)
            Button(action: send) {
                if sending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let account, account.mode == .apiKey else { return }
        let key = identity.apiKey(for: account.id)
        guard !key.isEmpty else {
            errorText = "This account has no API key set."
            return
        }

        draft = ""
        errorText = nil
        chat.append(ChatMessage(role: "user", text: text), to: deck.slug)
        sending = true

        let system = systemPrompt()
        let history = chat.messages(deck.slug)
        let model = account.model

        Task {
            do {
                let reply = try await AnthropicClient().reply(
                    system: system,
                    history: history,
                    apiKey: key,
                    model: model
                )
                chat.append(ChatMessage(role: "assistant", text: reply), to: deck.slug)
            } catch {
                errorText = error.localizedDescription
            }
            sending = false
        }
    }

    private func systemPrompt() -> String {
        let slug = deck.slug
        let todos = store.todos(slug)
            .map { "- [\($0.done ? "x" : " ")] \($0.text)" }
            .joined(separator: "\n")
        let links = store.links(slug)
            .map { "- \($0.label): \($0.url)" }
            .joined(separator: "\n")
        let own = identity.profile(slug).instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentSlug = deck.parent
        let instructions: String
        if own.isEmpty, let parentSlug {
            instructions = identity.profile(parentSlug).instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            instructions = own
        }
        let preamble = instructions.isEmpty ? "" : "Instructions for this workspace:\n\(instructions)\n\n"

        var sharedBlock = ""
        if let parentSlug, let parent = store.deck(parentSlug) {
            let shared = store.links(parentSlug)
                .map { "- \($0.label): \($0.url)" }
                .joined(separator: "\n")
            if !shared.isEmpty {
                sharedBlock = "\n\n# Shared from \(parent.name)\n\(shared)"
            }
        }

        return preamble + """
        You are the assistant for the "\(deck.name)" workspace only. Answer only from this workspace's content below. Never reference, infer, or reveal any other workspace or context. Be concise and direct.

        # To-dos
        \(todos.isEmpty ? "(none)" : todos)

        # Daily log
        \(store.daily(slug).isEmpty ? "(none)" : store.daily(slug))

        # Notes
        \(store.notes(slug).isEmpty ? "(none)" : store.notes(slug))

        # Links
        \(links.isEmpty ? "(none)" : links)
        """ + sharedBlock
    }
}
