import XCTest

@testable import Decks

final class DeckTreeTests: XCTestCase {
    private func deck(_ slug: String, parent: String? = nil, created: TimeInterval = 0) -> Deck {
        Deck(slug: slug, name: slug, createdAt: Date(timeIntervalSince1970: created), parent: parent)
    }

    func testApplyOrderListedFirstThenCreatedAt() {
        let decks = [deck("a", created: 1), deck("b", created: 2), deck("c", created: 3)]
        let ordered = DeckTree.applyOrder(decks, order: ["c", "a"])
        XCTAssertEqual(ordered.map(\.slug), ["c", "a", "b"])
    }

    func testApplyOrderEmptyFallsBackToCreatedAt() {
        let decks = [deck("b", created: 2), deck("a", created: 1)]
        XCTAssertEqual(DeckTree.applyOrder(decks, order: []).map(\.slug), ["a", "b"])
    }

    func testFlattenNestsChildrenUnderTheirParent() {
        let decks = [
            deck("equo"),
            deck("alpha", parent: "equo"),
            deck("invicto"),
            deck("beta", parent: "equo"),
        ]
        XCTAssertEqual(DeckTree.flatten(decks).map(\.slug), ["equo", "alpha", "beta", "invicto"])
    }

    func testFlattenKeepsOrphansAtTheEnd() {
        let decks = [deck("a"), deck("x", parent: "missing")]
        XCTAssertEqual(DeckTree.flatten(decks).map(\.slug), ["a", "x"])
    }

    func testCanBecomeChildOnlyWithoutChildren() {
        let decks = [deck("equo"), deck("alpha", parent: "equo")]
        XCTAssertFalse(DeckTree.canBecomeChild("equo", in: decks))
        XCTAssertTrue(DeckTree.canBecomeChild("alpha", in: decks))
    }

    func testValidParentEnforcesOneLevel() {
        let decks = [deck("equo"), deck("alpha", parent: "equo"), deck("solo")]
        XCTAssertTrue(DeckTree.isValidParent("equo", for: "solo", in: decks))
        XCTAssertFalse(DeckTree.isValidParent("solo", for: "solo", in: decks))
        XCTAssertFalse(DeckTree.isValidParent("alpha", for: "solo", in: decks))
        XCTAssertFalse(DeckTree.isValidParent("solo", for: "equo", in: decks))
        XCTAssertFalse(DeckTree.isValidParent("missing", for: "solo", in: decks))
    }
}
