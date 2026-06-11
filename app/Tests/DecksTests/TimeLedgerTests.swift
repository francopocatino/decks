import XCTest

@testable import Decks

final class TimeLedgerTests: XCTestCase {
    func testAddAccumulatesPerDay() {
        var ledger = TimeLedger()
        ledger.add(60, on: "2026-06-11")
        ledger.add(30, on: "2026-06-11")
        ledger.add(10, on: "2026-06-10")
        XCTAssertEqual(ledger.seconds(on: "2026-06-11"), 90)
        XCTAssertEqual(ledger.seconds(on: "2026-06-10"), 10)
        XCTAssertEqual(ledger.seconds(on: "2026-06-09"), 0)
    }

    func testTotalSumsRequestedDaysOnly() {
        var ledger = TimeLedger()
        ledger.add(100, on: "2026-06-11")
        ledger.add(50, on: "2026-06-04")
        XCTAssertEqual(ledger.total(over: ["2026-06-11", "2026-06-10"]), 100)
        XCTAssertEqual(ledger.total(over: ["2026-06-11", "2026-06-04"]), 150)
    }

    func testRecentDaysAreNewestFirstAndUnique() {
        let reference = ISO8601DateFormatter().date(from: "2026-06-11T15:00:00Z")!
        let days = TimeLedger.recentDays(3, endingAt: reference)
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0], TimeLedger.day(reference))
        XCTAssertEqual(Set(days).count, 3)
    }

    func testHourMinuteLabel() {
        XCTAssertEqual(TimeView.label(59), "0m")
        XCTAssertEqual(TimeView.label(1800), "30m")
        XCTAssertEqual(TimeView.label(3600), "1h 0m")
        XCTAssertEqual(TimeView.label(5520), "1h 32m")
    }
}
