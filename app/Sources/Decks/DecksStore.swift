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
    private var layoutByDeck: [String: DeckLayout] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var lastSignature = 0

    init() {
        Storage.ensureDirectory(Storage.root)
        load()
    }

    var activeDeck: Deck? {
        guard let activeSlug else { return nil }
        return decks.first { $0.slug == activeSlug }
    }

    var visibleDecks: [Deck] { decks.filter { !$0.isArchived } }

    var archivedDecks: [Deck] { decks.filter(\.isArchived) }

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
        decks = applyOrder(decks + [deck])
        todosByDeck[slug] = []
        linksByDeck[slug] = []
        dailyByDeck[slug] = ""
        notesByDeck[slug] = ""
        layoutByDeck[slug] = DeckLayout()
        select(slug)
    }

    func select(_ slug: String) {
        activeSlug = slug
        persistActive()
    }

    func renameDeck(_ slug: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = decks.firstIndex(where: { $0.slug == slug }) else { return }
        decks[index].name = trimmed
        persist(decks[index])
    }

    func setArchived(_ slug: String, _ archived: Bool) {
        guard let index = decks.firstIndex(where: { $0.slug == slug }) else { return }
        decks[index].archived = archived ? true : nil
        persist(decks[index])
        if archived, activeSlug == slug {
            activeSlug = visibleDecks.first?.slug
            persistActive()
        }
    }

    func moveDecks(fromOffsets source: IndexSet, toOffset destination: Int) {
        var visible = visibleDecks
        visible.move(fromOffsets: source, toOffset: destination)
        decks = visible + archivedDecks
        Storage.writeJSON(decks.map(\.slug), to: orderURL)
    }

    func deleteDeck(_ slug: String) {
        decks.removeAll { $0.slug == slug }
        if var order = Storage.readJSON([String].self, at: orderURL), order.contains(slug) {
            order.removeAll { $0 == slug }
            Storage.writeJSON(order, to: orderURL)
        }
        todosByDeck[slug] = nil
        linksByDeck[slug] = nil
        dailyByDeck[slug] = nil
        notesByDeck[slug] = nil
        layoutByDeck[slug] = nil
        try? FileManager.default.removeItem(at: Storage.deckDirectory(slug))
        if activeSlug == slug {
            activeSlug = visibleDecks.first?.slug
            persistActive()
        }
    }

    // MARK: To-dos

    func todos(_ slug: String) -> [Todo] { todosByDeck[slug] ?? [] }

    func openTodoCount(_ slug: String) -> Int { todos(slug).filter { !$0.done }.count }

    func addTodo(_ text: String, to slug: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todosByDeck[slug, default: []].insert(Todo(text: trimmed), at: 0)
        saveTodos(slug)
    }

    func editTodo(_ id: UUID, text: String, in slug: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var list = todosByDeck[slug],
              let index = list.firstIndex(where: { $0.id == id }), list[index].text != trimmed
        else { return }
        list[index].text = trimmed
        todosByDeck[slug] = list
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
        let url = Storage.deckDirectory(slug).appendingPathComponent("daily.md")
        scheduleSave("daily-\(slug)") { Storage.writeString(text, to: url) }
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
        let url = Storage.deckDirectory(slug).appendingPathComponent("notes.md")
        scheduleSave("notes-\(slug)") { Storage.writeString(text, to: url) }
    }

    // MARK: Layout

    func layout(_ slug: String) -> DeckLayout { layoutByDeck[slug] ?? DeckLayout() }

    func setLayout(_ layout: DeckLayout, for slug: String) {
        layoutByDeck[slug] = layout
        Storage.writeJSON(layout, to: Storage.deckDirectory(slug).appendingPathComponent("layout.json"))
    }

    // MARK: Loading

    private func load() {
        decks = readDecks()
        for deck in decks { loadContent(deck.slug) }
        let state = Storage.readJSON(State.self, at: stateURL)
        activeSlug = state?.active ?? decks.first?.slug
        lastSignature = Self.directorySignature()
    }

    func reloadIfChanged() {
        let signature = Self.directorySignature()
        guard signature != lastSignature else { return }
        lastSignature = signature
        decks = readDecks()
        for deck in decks { loadContent(deck.slug) }
        if let active = activeSlug, !decks.contains(where: { $0.slug == active }) {
            activeSlug = visibleDecks.first?.slug
            persistActive()
        }
    }

    private static func directorySignature() -> Int {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: Storage.root,
            includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        var hasher = Hasher()
        for case let url as URL in enumerator {
            let date = (try? url.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            hasher.combine(url.path)
            hasher.combine(date)
        }
        return hasher.finalize()
    }

    private func readDecks() -> [Deck] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: Storage.root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        let decks = entries.compactMap { Storage.readJSON(Deck.self, at: $0.appendingPathComponent("deck.json")) }
        return applyOrder(decks)
    }

    private func applyOrder(_ decks: [Deck]) -> [Deck] {
        let order = Storage.readJSON([String].self, at: orderURL) ?? []
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return decks.sorted { lhs, rhs in
            switch (position[lhs.slug], position[rhs.slug]) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private func loadContent(_ slug: String) {
        let directory = Storage.deckDirectory(slug)
        todosByDeck[slug] = Storage.readJSON([Todo].self, at: directory.appendingPathComponent("todos.json")) ?? []
        linksByDeck[slug] = Storage.readJSON([Link].self, at: directory.appendingPathComponent("links.json")) ?? []
        if saveTasks["daily-\(slug)"] == nil {
            dailyByDeck[slug] = Storage.readString(directory.appendingPathComponent("daily.md"))
        }
        if saveTasks["notes-\(slug)"] == nil {
            notesByDeck[slug] = Storage.readString(directory.appendingPathComponent("notes.md"))
        }
        var layout = Storage.readJSON(DeckLayout.self, at: directory.appendingPathComponent("layout.json")) ?? DeckLayout()
        layout.normalize()
        layoutByDeck[slug] = layout
    }

    // MARK: Helpers

    private func persist(_ deck: Deck) {
        Storage.writeJSON(deck, to: Storage.deckDirectory(deck.slug).appendingPathComponent("deck.json"))
    }

    private func persistActive() {
        Storage.writeJSON(State(active: activeSlug), to: stateURL)
    }

    private func scheduleSave(_ key: String, write: @escaping @MainActor () -> Void) {
        saveTasks[key]?.cancel()
        saveTasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            write()
            self?.saveTasks[key] = nil
        }
    }

    private var stateURL: URL { Storage.root.appendingPathComponent("state.json") }

    private var orderURL: URL { Storage.root.appendingPathComponent("order.json") }

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
