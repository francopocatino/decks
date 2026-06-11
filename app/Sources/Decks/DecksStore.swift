import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DecksStore {
    private(set) var decks: [Deck] = []
    var activeSlug: String?
    var settingsSection: SettingsSection = .general
    var settingsDeck: String?

    private var todosByDeck: [String: [Todo]] = [:]
    private var linksByDeck: [String: [Link]] = [:]
    private var dailyByDeck: [String: String] = [:]
    private var notesByDeck: [String: String] = [:]
    private var layoutByDeck: [String: DeckLayout] = [:]
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var pendingWrites: [String: @MainActor () -> Void] = [:]
    private var lastDeckSignatures: [String: Int] = [:]
    private var lastOrderSignature = 0
    @ObservationIgnored var onTodosChanged: ((String) -> Void)?

    init() {
        Storage.ensureDirectory(Storage.root)
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSaves() }
        }
    }

    var activeDeck: Deck? {
        guard let activeSlug else { return nil }
        return decks.first { $0.slug == activeSlug }
    }

    func deck(_ slug: String) -> Deck? { decks.first { $0.slug == slug } }

    var visibleDecks: [Deck] { decks.filter { !$0.isArchived } }

    var archivedDecks: [Deck] { decks.filter(\.isArchived) }

    func topLevelVisibleDecks() -> [Deck] {
        visibleDecks.filter { $0.parent == nil }
    }

    func visibleChildren(of slug: String) -> [Deck] {
        visibleDecks.filter { $0.parent == slug }
    }

    func canHaveParent(_ slug: String) -> Bool {
        DeckTree.canBecomeChild(slug, in: decks)
    }

    func parentCandidates(for slug: String) -> [Deck] {
        decks.filter { $0.slug != slug && $0.parent == nil && !$0.isArchived }
    }

    // MARK: Decks

    func createDeck(name: String, parent: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = Self.slugify(trimmed)
        guard !slug.isEmpty else { return }
        guard !decks.contains(where: { $0.slug == slug }) else {
            select(slug)
            return
        }
        var deck = Deck(slug: slug, name: trimmed, createdAt: Date())
        if let parent, decks.contains(where: { $0.slug == parent && $0.parent == nil }) {
            deck.parent = parent
        }
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

    func setColor(_ color: String?, for slug: String) {
        guard let index = decks.firstIndex(where: { $0.slug == slug }) else { return }
        decks[index].color = color
        persist(decks[index])
    }

    func setArchived(_ slug: String, _ archived: Bool) {
        guard let index = decks.firstIndex(where: { $0.slug == slug }) else { return }
        decks[index].archived = archived ? true : nil
        persist(decks[index])
        if archived {
            for child in decks.indices where decks[child].parent == slug {
                decks[child].parent = nil
                persist(decks[child])
            }
        }
        if archived, activeSlug == slug {
            activeSlug = visibleDecks.first?.slug
            persistActive()
        }
    }

    func setParent(_ slug: String, to parent: String?) {
        guard let index = decks.firstIndex(where: { $0.slug == slug }) else { return }
        guard let parent else {
            decks[index].parent = nil
            persist(decks[index])
            return
        }
        guard DeckTree.isValidParent(parent, for: slug, in: decks) else { return }
        decks[index].parent = parent
        persist(decks[index])
        decks = flattened(decks)
        Storage.writeJSON(decks.map(\.slug), to: orderURL)
    }

    func moveDecks(parent: String?, fromOffsets source: IndexSet, toOffset destination: Int) {
        var group = decks.filter { $0.parent == parent && !$0.isArchived }
        group.move(fromOffsets: source, toOffset: destination)
        let rest = decks.filter { !($0.parent == parent && !$0.isArchived) }
        decks = flattened(group + rest)
        Storage.writeJSON(decks.map(\.slug), to: orderURL)
    }

    private func flattened(_ all: [Deck]) -> [Deck] {
        DeckTree.flatten(all)
    }

    func deleteDeck(_ slug: String) {
        for index in decks.indices where decks[index].parent == slug {
            decks[index].parent = nil
            persist(decks[index])
        }
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

    func replaceTodos(_ todos: [Todo], for slug: String) {
        todosByDeck[slug] = todos
        saveTodos(slug)
    }

    private func saveTodos(_ slug: String) {
        Storage.writeJSON(todosByDeck[slug] ?? [], to: Storage.deckDirectory(slug).appendingPathComponent("todos.json"))
        onTodosChanged?(slug)
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

    func editLink(_ id: UUID, label: String, url: String, in slug: String) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty, var list = linksByDeck[slug],
              let index = list.firstIndex(where: { $0.id == id })
        else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        list[index].label = cleanLabel.isEmpty ? cleanURL : cleanLabel
        list[index].url = cleanURL
        linksByDeck[slug] = list
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
        let header = "## \(Self.dailyDate())\n\n"
        let current = dailyByDeck[slug] ?? ""
        guard !current.hasPrefix(header) else { return }
        setDaily(current.isEmpty ? header : header + current, for: slug)
    }

    func addDailyLine(_ text: String, to slug: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let header = "## \(Self.dailyDate())\n\n"
        let current = dailyByDeck[slug] ?? ""
        let next: String
        if current.hasPrefix(header) {
            next = header + trimmed + "\n\n" + current.dropFirst(header.count)
        } else if current.isEmpty {
            next = header + trimmed + "\n\n"
        } else {
            next = header + trimmed + "\n\n" + current
        }
        setDaily(next, for: slug)
    }

    static func dailyDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date.now)
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
        lastDeckSignatures = Self.deckSignatures()
        lastOrderSignature = Self.fileSignature(orderURL)
    }

    func reloadIfChanged() {
        let signatures = Self.deckSignatures()
        let orderSignature = Self.fileSignature(orderURL)
        guard signatures != lastDeckSignatures || orderSignature != lastOrderSignature else { return }

        let removed = Set(lastDeckSignatures.keys).subtracting(signatures.keys)
        let changed = signatures.filter { lastDeckSignatures[$0.key] != $0.value }.map(\.key)
        lastDeckSignatures = signatures
        lastOrderSignature = orderSignature

        decks = readDecks()
        for slug in changed { loadContent(slug) }
        for slug in removed { dropContent(slug) }
        if let active = activeSlug, !decks.contains(where: { $0.slug == active }) {
            activeSlug = visibleDecks.first?.slug
            persistActive()
        }
    }

    private func dropContent(_ slug: String) {
        todosByDeck[slug] = nil
        linksByDeck[slug] = nil
        dailyByDeck[slug] = nil
        notesByDeck[slug] = nil
        layoutByDeck[slug] = nil
    }

    private static func deckSignatures() -> [String: Int] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: Storage.root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [:] }

        var result: [String: Int] = [:]
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(
                      at: dir,
                      includingPropertiesForKeys: [.contentModificationDateKey]
                  )
            else { continue }

            var hasher = Hasher()
            var isDeck = false
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if file.pathExtension == "corrupt" { continue }
                if file.lastPathComponent == "deck.json" { isDeck = true }
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                hasher.combine(file.lastPathComponent)
                hasher.combine(date)
            }
            if isDeck { result[dir.lastPathComponent] = hasher.finalize() }
        }
        return result
    }

    private static func fileSignature(_ url: URL) -> Int {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        var hasher = Hasher()
        hasher.combine(date)
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
        DeckTree.applyOrder(decks, order: Storage.readJSON([String].self, at: orderURL) ?? [])
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
        layoutByDeck[slug] = Storage.readJSON(DeckLayout.self, at: directory.appendingPathComponent("layout.json")) ?? DeckLayout()
    }

    // MARK: Helpers

    private func persist(_ deck: Deck) {
        Storage.writeJSON(deck, to: Storage.deckDirectory(deck.slug).appendingPathComponent("deck.json"))
    }

    private func persistActive() {
        Storage.writeJSON(State(active: activeSlug), to: stateURL)
    }

    private func scheduleSave(_ key: String, write: @escaping @MainActor () -> Void) {
        pendingWrites[key] = write
        saveTasks[key]?.cancel()
        saveTasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            self?.flush(key)
        }
    }

    private func flush(_ key: String) {
        pendingWrites[key]?()
        pendingWrites[key] = nil
        saveTasks[key] = nil
    }

    func flushPendingSaves() {
        for key in Array(pendingWrites.keys) {
            saveTasks[key]?.cancel()
            flush(key)
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
