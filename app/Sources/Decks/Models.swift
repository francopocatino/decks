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
    case daily, todos, notes, links, meetings, time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .todos: "To-dos"
        case .notes: "Notes"
        case .links: "Links"
        case .meetings: "Meetings"
        case .time: "Time"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "calendar"
        case .todos: "checklist"
        case .notes: "note.text"
        case .links: "link"
        case .meetings: "person.2"
        case .time: "clock"
        }
    }
}

enum SplitAxis: String, Codable, Hashable {
    case horizontal, vertical
}

// A recursive pane tree: a leaf shows one section; a split holds two
// children with an axis and the first child's size fraction (0...1).
indirect enum PaneNode: Codable, Hashable {
    case leaf(DeckSection)
    case split(SplitAxis, Double, PaneNode, PaneNode)
}

struct DeckLayout: Codable, Hashable {
    var root: PaneNode

    init() {
        root = .leaf(.daily)
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
    var due: Date?
    var reminderID: String?

    init(text: String) {
        id = UUID()
        self.text = text
        done = false
        createdAt = Date()
        doneAt = nil
        due = nil
        reminderID = nil
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

    // `note` is optional on the CLI side; tolerate a record that omits it
    // instead of failing the whole links.json decode (and backing it up).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        url = try container.decode(String.self, forKey: .url)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}
