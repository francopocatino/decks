import Foundation
import Observation

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID
    var role: String
    var text: String
    var at: Date

    init(role: String, text: String) {
        id = UUID()
        self.role = role
        self.text = text
        at = Date()
    }
}

@MainActor
@Observable
final class ChatStore {
    private var byDeck: [String: [ChatMessage]] = [:]

    func messages(_ slug: String) -> [ChatMessage] {
        byDeck[slug] ?? Storage.readJSON([ChatMessage].self, at: url(slug)) ?? []
    }

    func append(_ message: ChatMessage, to slug: String) {
        var list = messages(slug)
        list.append(message)
        byDeck[slug] = list
        persist(slug)
    }

    func clear(_ slug: String) {
        byDeck[slug] = []
        persist(slug)
    }

    func forget(_ slug: String) {
        byDeck[slug] = nil
    }

    private func persist(_ slug: String) {
        Storage.writeJSON(byDeck[slug] ?? [], to: url(slug))
    }

    private func url(_ slug: String) -> URL {
        Storage.deckDirectory(slug).appendingPathComponent("chat.json")
    }
}
