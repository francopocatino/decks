import XCTest

@testable import Decks

final class DeckDigestTests: XCTestCase {
    private let deck = Deck(slug: "acme", name: "Acme", createdAt: Date())

    func testDigestIncludesOnlyNonEmptySections() {
        let digest = DeckDigest.markdown(deck: deck, todos: [], links: [], daily: "", notes: "  ")
        XCTAssertEqual(digest, "# Acme\n")
    }

    func testDigestRendersOpenTodosLinksDailyAndNotes() {
        var done = Todo(text: "shipped")
        done.done = true
        let digest = DeckDigest.markdown(
            deck: deck,
            todos: [Todo(text: "review PR"), done],
            links: [Link(label: "Repo", url: "https://github.com/x")],
            daily: "## 2026-06-11\n\nworked",
            notes: "remember the thing"
        )
        XCTAssertTrue(digest.contains("- [ ] review PR"))
        XCTAssertFalse(digest.contains("shipped"))
        XCTAssertTrue(digest.contains("## Daily"))
        XCTAssertTrue(digest.contains("## Notes\n\nremember the thing"))
        XCTAssertTrue(digest.contains("- [Repo](https://github.com/x)"))
    }

    func testDueDateAnnotatesTodoLine() {
        var todo = Todo(text: "pay invoice")
        todo.due = Date(timeIntervalSince1970: 1_750_000_000)
        let digest = DeckDigest.markdown(deck: deck, todos: [todo], links: [], daily: "", notes: "")
        XCTAssertTrue(digest.contains("- [ ] pay invoice (due "))
    }

    func testFilenameUsesSlug() {
        XCTAssertEqual(DeckDigest.filename(for: deck), "acme.md")
    }
}
