import Foundation
import Observation

// Read-only markdown digest of a deck, mirrored into iCloud Drive so notes
// are readable from the Files app on iPhone. One-way by design: ~/.decks
// stays the source of truth and never lives inside a sync folder.
enum DeckDigest {
    static func markdown(deck: Deck, todos: [Todo], links: [Link], daily: String, notes: String) -> String {
        var sections = ["# \(deck.name)"]

        let open = todos.filter { !$0.done }
        if !open.isEmpty {
            let lines = open.map { todo in
                var line = "- [ ] \(todo.text)"
                if let due = todo.due {
                    line += " (due \(due.formatted(date: .abbreviated, time: .shortened)))"
                }
                return line
            }
            sections.append("## To-dos\n\n\(lines.joined(separator: "\n"))")
        }

        let trimmedDaily = daily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDaily.isEmpty {
            sections.append("## Daily\n\n\(trimmedDaily)")
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            sections.append("## Notes\n\n\(trimmedNotes)")
        }

        if !links.isEmpty {
            let lines = links.map { "- [\($0.label)](\($0.url))" }
            sections.append("## Links\n\n\(lines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    static func filename(for deck: Deck) -> String {
        "\(deck.slug).md"
    }
}

@MainActor
@Observable
final class CloudMirrorEngine {
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private var written: [String: Int] = [:]
    @ObservationIgnored private var lastRun = Date.distantPast

    init(store: DecksStore) {
        self.store = store
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Decks", isDirectory: true)
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path)
    }

    func tick() {
        guard UserDefaults.standard.bool(forKey: "icloudMirror"), Self.isAvailable else { return }
        guard Date().timeIntervalSince(lastRun) > 30 else { return }
        lastRun = Date()
        Storage.ensureDirectory(Self.folder)

        var current: Set<String> = []
        for deck in store.visibleDecks {
            let digest = DeckDigest.markdown(
                deck: deck,
                todos: store.todos(deck.slug),
                links: store.links(deck.slug),
                daily: store.daily(deck.slug),
                notes: store.notes(deck.slug)
            )
            let name = DeckDigest.filename(for: deck)
            current.insert(name)
            var hasher = Hasher()
            hasher.combine(digest)
            let signature = hasher.finalize()
            guard written[name] != signature else { continue }
            written[name] = signature
            Storage.writeString(digest, to: Self.folder.appendingPathComponent(name))
        }

        // The Decks folder is app-managed: drop digests of removed decks.
        let existing = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in existing where file.pathExtension == "md" && !current.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            written[file.lastPathComponent] = nil
        }
    }
}
