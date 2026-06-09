import Foundation

enum DeckTree {
    static func applyOrder(_ decks: [Deck], order: [String]) -> [Deck] {
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

    static func flatten(_ all: [Deck]) -> [Deck] {
        var result: [Deck] = []
        for top in all.filter({ $0.parent == nil }) {
            result.append(top)
            result.append(contentsOf: all.filter { $0.parent == top.slug })
        }
        let included = Set(result.map(\.slug))
        result.append(contentsOf: all.filter { !included.contains($0.slug) })
        return result
    }

    static func canBecomeChild(_ slug: String, in decks: [Deck]) -> Bool {
        !decks.contains { $0.parent == slug }
    }

    static func isValidParent(_ parent: String, for slug: String, in decks: [Deck]) -> Bool {
        guard parent != slug,
              let target = decks.first(where: { $0.slug == parent }), target.parent == nil
        else { return false }
        return canBecomeChild(slug, in: decks)
    }
}
