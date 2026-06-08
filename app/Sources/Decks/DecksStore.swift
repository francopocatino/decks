import Foundation
import Observation

@MainActor
@Observable
final class DecksStore {
    private(set) var decks: [Deck] = []
    var activeSlug: String?

    private var todosByDeck: [String: [Todo]] = [:]
    private var linksByDeck: [String: [Link]] = [:]
    private var dailyByDeck: [String: String] = [:]
    private var notesByDeck: [String: String] = [:]

    init() {
        Storage.ensureDirectory(Storage.root)
        load()
    }

    var activeDeck: Deck? {
        guard let activeSlug else { return nil }
        return decks.first { $0.slug == activeSlug }
    }

    // MARK: Decks

    func createDeck(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = Self.slugify(trimmed)
        guard !slug.isEmpty else { return }
        guard !decks.contains(where: { $0.slug == slug }) else {
            select(slug)
            return
        }
        let deck = Deck(slug: slug, name: trimmed, createdAt: Date())
        let directory = Storage.deckDirectory(slug)
        Storage.ensureDirectory(directory)
        Storage.writeJSON(deck, to: directory.appendingPathComponent("deck.json"))
        decks.append(deck)
        decks.sort { $0.createdAt < $1.createdAt }
        todosByDeck[slug] = []
        linksByDeck[slug] = []
        dailyByDeck[slug] = ""
        notesByDeck[slug] = ""
        select(slug)
    }

    func select(_ slug: String) {
        activeSlug = slug
        Storage.writeJSON(State(active: slug), to: stateURL)
    }

    // MARK: To-dos

    func todos(_ slug: String) -> [Todo] { todosByDeck[slug] ?? [] }

    func addTodo(_ text: String, to slug: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todosByDeck[slug, default: []].insert(Todo(text: trimmed), at: 0)
        saveTodos(slug)
    }

    func toggleTodo(_ id: UUID, in slug: String) {
        guard var list = todosByDeck[slug], let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].done.toggle()
        list[index].doneAt = list[index].done ? Date() : nil
        todosByDeck[slug] = list
        saveTodos(slug)
    }

    func deleteTodo(_ id: UUID, in slug: String) {
        todosByDeck[slug]?.removeAll { $0.id == id }
        saveTodos(slug)
    }

    private func saveTodos(_ slug: String) {
        Storage.writeJSON(todosByDeck[slug] ?? [], to: Storage.deckDirectory(slug).appendingPathComponent("todos.json"))
    }

    // MARK: Links

    func links(_ slug: String) -> [Link] { linksByDeck[slug] ?? [] }

    func addLink(label: String, url: String, to slug: String) {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        linksByDeck[slug, default: []].append(Link(label: cleanLabel.isEmpty ? cleanURL : cleanLabel, url: cleanURL))
        saveLinks(slug)
    }

    func deleteLink(_ id: UUID, in slug: String) {
        linksByDeck[slug]?.removeAll { $0.id == id }
        saveLinks(slug)
    }

    private func saveLinks(_ slug: String) {
        Storage.writeJSON(linksByDeck[slug] ?? [], to: Storage.deckDirectory(slug).appendingPathComponent("links.json"))
    }

    // MARK: Daily & Notes

    func daily(_ slug: String) -> String { dailyByDeck[slug] ?? "" }

    func setDaily(_ text: String, for slug: String) {
        dailyByDeck[slug] = text
        Storage.writeString(text, to: Storage.deckDirectory(slug).appendingPathComponent("daily.md"))
    }

    func appendDailyEntry(to slug: String) {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        let header = "## \(date)\n\n"
        let current = dailyByDeck[slug] ?? ""
        setDaily(current.isEmpty ? header : header + "\n" + current, for: slug)
    }

    func notes(_ slug: String) -> String { notesByDeck[slug] ?? "" }

    func setNotes(_ text: String, for slug: String) {
        notesByDeck[slug] = text
        Storage.writeString(text, to: Storage.deckDirectory(slug).appendingPathComponent("notes.md"))
    }

    // MARK: Loading

    private func load() {
        decks = readDecks().sorted { $0.createdAt < $1.createdAt }
        for deck in decks { loadContent(deck.slug) }
        let state = Storage.readJSON(State.self, at: stateURL)
        activeSlug = state?.active ?? decks.first?.slug
    }

    private func readDecks() -> [Deck] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Storage.root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries.compactMap { Storage.readJSON(Deck.self, at: $0.appendingPathComponent("deck.json")) }
    }

    private func loadContent(_ slug: String) {
        let directory = Storage.deckDirectory(slug)
        todosByDeck[slug] = Storage.readJSON([Todo].self, at: directory.appendingPathComponent("todos.json")) ?? []
        linksByDeck[slug] = Storage.readJSON([Link].self, at: directory.appendingPathComponent("links.json")) ?? []
        dailyByDeck[slug] = Storage.readString(directory.appendingPathComponent("daily.md"))
        notesByDeck[slug] = Storage.readString(directory.appendingPathComponent("notes.md"))
    }

    // MARK: Helpers

    private var stateURL: URL { Storage.root.appendingPathComponent("state.json") }

    static func slugify(_ name: String) -> String {
        let mapped = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private struct State: Codable {
        var active: String?
    }
}
