import CoreSpotlight
import Foundation
import Observation

// What gets indexed for one deck. Pure, so the entry-building policy is
// unit-testable; CSSearchableItem construction stays a thin mapping.
struct SpotlightEntry: Hashable {
    var id: String
    var title: String
    var text: String

    static func entries(deck: Deck, todos: [Todo], links: [Link], notes: String, daily: String) -> [SpotlightEntry] {
        var result = [SpotlightEntry(id: "deck/\(deck.slug)", title: deck.name, text: "Deck")]
        for todo in todos where !todo.done {
            result.append(SpotlightEntry(id: "todo/\(deck.slug)/\(todo.id.uuidString)", title: todo.text, text: "To-do · \(deck.name)"))
        }
        for link in links {
            result.append(SpotlightEntry(id: "link/\(deck.slug)/\(link.id.uuidString)", title: link.label, text: link.url))
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            result.append(SpotlightEntry(id: "notes/\(deck.slug)", title: "\(deck.name) notes", text: trimmedNotes))
        }
        let trimmedDaily = daily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDaily.isEmpty {
            result.append(SpotlightEntry(id: "daily/\(deck.slug)", title: "\(deck.name) daily", text: trimmedDaily))
        }
        return result
    }

    static func slug(fromIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }
}

@MainActor
@Observable
final class SpotlightIndexer {
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private var indexed: [String: Int] = [:]
    @ObservationIgnored private var lastRun = Date.distantPast

    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    init(store: DecksStore) {
        self.store = store
    }

    func tick() {
        guard Self.isSupported else { return }
        guard Date().timeIntervalSince(lastRun) > 10 else { return }
        lastRun = Date()

        let index = CSSearchableIndex.default()
        var seen: Set<String> = []
        for deck in store.visibleDecks {
            seen.insert(deck.slug)
            let entries = SpotlightEntry.entries(
                deck: deck,
                todos: store.todos(deck.slug),
                links: store.links(deck.slug),
                notes: store.notes(deck.slug),
                daily: store.daily(deck.slug)
            )
            var hasher = Hasher()
            hasher.combine(entries)
            let signature = hasher.finalize()
            guard indexed[deck.slug] != signature else { continue }
            indexed[deck.slug] = signature
            // Operations on one index instance run in submission order, so the
            // re-add right after the domain wipe is safe.
            index.deleteSearchableItems(withDomainIdentifiers: [domain(deck.slug)], completionHandler: nil)
            add(entries, deck: deck.slug, to: index)
        }
        let removed = Set(indexed.keys).subtracting(seen)
        for slug in removed {
            indexed[slug] = nil
            index.deleteSearchableItems(withDomainIdentifiers: [domain(slug)], completionHandler: nil)
        }
    }

    private func add(_ entries: [SpotlightEntry], deck slug: String, to index: CSSearchableIndex) {
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.title
            attributes.contentDescription = entry.text
            let item = CSSearchableItem(
                uniqueIdentifier: entry.id,
                domainIdentifier: domain(slug),
                attributeSet: attributes
            )
            return item
        }
        guard !items.isEmpty else { return }
        index.indexSearchableItems(items, completionHandler: nil)
    }

    private func domain(_ slug: String) -> String {
        "deck-\(slug)"
    }
}
