import Foundation

enum DeckSection: String, CaseIterable, Identifiable {
    case daily, todos, notes, links

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .todos: "To-dos"
        case .notes: "Notes"
        case .links: "Links"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "calendar"
        case .todos: "checklist"
        case .notes: "note.text"
        case .links: "link"
        }
    }
}

struct Deck: Identifiable, Codable, Hashable {
    var slug: String
    var name: String
    var createdAt: Date

    var id: String { slug }
}

struct Todo: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var done: Bool
    var createdAt: Date
    var doneAt: Date?

    init(text: String) {
        id = UUID()
        self.text = text
        done = false
        createdAt = Date()
        doneAt = nil
    }
}

struct Link: Identifiable, Codable, Hashable {
    var id: UUID
    var label: String
    var url: String
    var note: String

    init(label: String, url: String, note: String = "") {
        id = UUID()
        self.label = label
        self.url = url
        self.note = note
    }
}
