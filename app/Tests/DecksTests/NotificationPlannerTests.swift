import XCTest

@testable import Decks

final class NotificationPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func meeting(_ id: String, startsIn minutes: Double, link: String? = nil) -> Meeting {
        let start = now.addingTimeInterval(minutes * 60)
        return Meeting(id: id, title: id, start: start, end: start.addingTimeInterval(1800), link: link.flatMap(URL.init))
    }

    private func todo(_ text: String, dueIn minutes: Double?, done: Bool = false) -> Todo {
        var todo = Todo(text: text)
        todo.due = minutes.map { now.addingTimeInterval($0 * 60) }
        todo.done = done
        return todo
    }

    func testMeetingFiresLeadMinutesBefore() {
        let planned = NotificationPlanner.plan(
            meetings: [meeting("standup", startsIn: 30, link: "https://meet.google.com/abc")],
            todos: [],
            leadMinutes: 5,
            now: now
        )
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].fireDate, now.addingTimeInterval(25 * 60))
        XCTAssertEqual(planned[0].url, "https://meet.google.com/abc")
        XCTAssertEqual(planned[0].id, "meeting-standup")
    }

    func testMeetingAlreadyInsideLeadWindowIsSkipped() {
        let planned = NotificationPlanner.plan(
            meetings: [meeting("imminent", startsIn: 1)],
            todos: [],
            leadMinutes: 5,
            now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testDuplicateMeetingIDsCollapse() {
        let planned = NotificationPlanner.plan(
            meetings: [meeting("m", startsIn: 30), meeting("m", startsIn: 30)],
            todos: [],
            leadMinutes: 2,
            now: now
        )
        XCTAssertEqual(planned.count, 1)
    }

    func testOpenTodoWithFutureDueIsPlanned() {
        let planned = NotificationPlanner.plan(
            meetings: [],
            todos: [("Acme", todo("ship", dueIn: 60))],
            leadMinutes: 2,
            now: now
        )
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].fireDate, now.addingTimeInterval(3600))
        XCTAssertTrue(planned[0].body.contains("Acme"))
    }

    func testDoneOverdueAndUndatedTodosAreSkipped() {
        let planned = NotificationPlanner.plan(
            meetings: [],
            todos: [
                ("Acme", todo("done", dueIn: 60, done: true)),
                ("Acme", todo("overdue", dueIn: -60)),
                ("Acme", todo("undated", dueIn: nil)),
            ],
            leadMinutes: 2,
            now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    func testPlanIsSortedAndCapped() {
        let meetings = (0..<80).map { meeting("m\($0)", startsIn: Double(10 + $0)) }
        let planned = NotificationPlanner.plan(meetings: meetings, todos: [], leadMinutes: 2, now: now)
        XCTAssertEqual(planned.count, NotificationPlanner.limit)
        XCTAssertEqual(planned, planned.sorted { $0.fireDate < $1.fireDate })
    }
}
