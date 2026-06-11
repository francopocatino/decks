import XCTest

@testable import Decks

final class SpotlightEntryTests: XCTestCase {
    private let deck = Deck(slug: "acme", name: "Acme", createdAt: Date())

    func testIndexesDeckOpenTodosLinksNotesAndDaily() {
        var done = Todo(text: "shipped")
        done.done = true
        let entries = SpotlightEntry.entries(
            deck: deck,
            todos: [Todo(text: "review PR"), done],
            links: [Link(label: "Repo", url: "https://github.com/x")],
            notes: "some notes",
            daily: "## 2026-06-11\n\nworked"
        )
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries[0].id, "deck/acme")
        XCTAssertTrue(entries.contains { $0.title == "review PR" })
        XCTAssertFalse(entries.contains { $0.title == "shipped" })
        XCTAssertTrue(entries.contains { $0.id == "notes/acme" })
        XCTAssertTrue(entries.contains { $0.id == "daily/acme" })
    }

    func testEmptyNotesAndDailyAreSkipped() {
        let entries = SpotlightEntry.entries(deck: deck, todos: [], links: [], notes: "  \n", daily: "")
        XCTAssertEqual(entries.map(\.id), ["deck/acme"])
    }

    func testSlugParsesFromAnyEntryIdentifier() {
        XCTAssertEqual(SpotlightEntry.slug(fromIdentifier: "deck/acme"), "acme")
        XCTAssertEqual(SpotlightEntry.slug(fromIdentifier: "todo/acme/ABC"), "acme")
        XCTAssertNil(SpotlightEntry.slug(fromIdentifier: "garbage"))
    }
}
