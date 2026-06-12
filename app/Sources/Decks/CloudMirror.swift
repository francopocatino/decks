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
    @ObservationIgnored private var throttle = Throttle(30)

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
        guard UserDefaults.standard.bool(forKey: Pref.icloudMirror), Self.isAvailable else { return }
        guard throttle.ready() else { return }
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
            let url = Self.folder.appendingPathComponent(name)
            guard written[name] != signature || !FileManager.default.fileExists(atPath: url.path) else { continue }
            written[name] = signature
            Storage.writeString(digest, to: url)
        }

        // Prune only digests this app wrote (tracked in the manifest):
        // anything the user drops into the folder is left alone.
        let manifest = Set(UserDefaults.standard.stringArray(forKey: Pref.cloudMirrorFiles) ?? [])
        for name in manifest.subtracting(current) {
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(name))
            written[name] = nil
        }
        if manifest != current {
            UserDefaults.standard.set(Array(current).sorted(), forKey: Pref.cloudMirrorFiles)
        }
    }
}
