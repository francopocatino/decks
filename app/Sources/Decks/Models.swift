import Foundation

enum SettingsSection: String, Hashable, CaseIterable, Identifiable {
    case general, connectors, decks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .connectors: "Connectors"
        case .decks: "Decks"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .connectors: "powerplug"
        case .decks: "rectangle.stack"
        }
    }
}

enum DeckSection: String, Codable, CaseIterable, Identifiable {
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

enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case single, columns, stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "Single"
        case .columns: "Two columns"
        case .stack: "Stack + side"
        }
    }

    var symbol: String {
        switch self {
        case .single: "rectangle"
        case .columns: "rectangle.split.2x1"
        case .stack: "rectangle.split.3x1"
        }
    }

    var paneCount: Int {
        switch self {
        case .single: 1
        case .columns: 2
        case .stack: 3
        }
    }
}

struct DeckLayout: Codable, Hashable {
    var mode: LayoutMode
    var slots: [DeckSection]

    init() {
        mode = .single
        slots = [.daily, .todos, .notes]
    }

    mutating func normalize() {
        let defaults: [DeckSection] = [.daily, .todos, .notes]
        while slots.count < defaults.count { slots.append(defaults[slots.count]) }
    }
}

struct Deck: Identifiable, Codable, Hashable {
    var slug: String
    var name: String
    var createdAt: Date
    var archived: Bool?
    var parent: String?
    var color: String?

    var id: String { slug }
    var isArchived: Bool { archived ?? false }
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
