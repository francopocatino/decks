import XCTest

@testable import Decks

final class RemindersMergeTests: XCTestCase {
    private func todo(_ text: String, done: Bool = false, reminderID: String? = nil) -> Todo {
        var todo = Todo(text: text)
        todo.done = done
        todo.doneAt = done ? Date() : nil
        todo.reminderID = reminderID
        return todo
    }

    private func remote(_ id: String, _ text: String, done: Bool = false) -> RemindersMerge.Remote {
        RemindersMerge.Remote(id: id, text: text, done: done, completedAt: done ? Date() : nil)
    }

    private func snap(_ text: String, done: Bool = false) -> RemindersMerge.Snapshot {
        RemindersMerge.Snapshot(text: text, done: done)
    }

    func testNewLocalTodoIsCreatedRemotely() {
        let todo = todo("ship it")
        let plan = RemindersMerge.plan(todos: [todo], remotes: [], snapshot: [:])
        XCTAssertEqual(plan.createRemote, [todo.id])
        XCTAssertEqual(plan.todos.map(\.text), ["ship it"])
        XCTAssertTrue(plan.updateRemote.isEmpty)
        XCTAssertTrue(plan.deleteRemote.isEmpty)
    }

    func testNewReminderCreatesLocalTodo() {
        let plan = RemindersMerge.plan(todos: [todo("existing")], remotes: [remote("R1", "from siri")], snapshot: [:])
        XCTAssertEqual(plan.todos.map(\.text), ["from siri", "existing"])
        XCTAssertEqual(plan.todos.first?.reminderID, "R1")
        XCTAssertEqual(plan.snapshot["R1"], snap("from siri"))
    }

    func testRemoteEditPropagatesToTodo() {
        let linked = todo("old", reminderID: "R1")
        let plan = RemindersMerge.plan(
            todos: [linked],
            remotes: [remote("R1", "new")],
            snapshot: ["R1": snap("old")]
        )
        XCTAssertEqual(plan.todos.map(\.text), ["new"])
        XCTAssertTrue(plan.updateRemote.isEmpty)
        XCTAssertEqual(plan.snapshot["R1"], snap("new"))
    }

    func testRemoteCompletionPropagatesToTodo() {
        let linked = todo("task", reminderID: "R1")
        let plan = RemindersMerge.plan(
            todos: [linked],
            remotes: [remote("R1", "task", done: true)],
            snapshot: ["R1": snap("task")]
        )
        XCTAssertTrue(plan.todos[0].done)
        XCTAssertNotNil(plan.todos[0].doneAt)
    }

    func testLocalEditPropagatesToReminder() {
        let linked = todo("new", reminderID: "R1")
        let plan = RemindersMerge.plan(
            todos: [linked],
            remotes: [remote("R1", "old")],
            snapshot: ["R1": snap("old")]
        )
        XCTAssertEqual(plan.updateRemote.map(\.text), ["new"])
        XCTAssertEqual(plan.todos.map(\.text), ["new"])
        XCTAssertEqual(plan.snapshot["R1"], snap("new"))
    }

    func testConflictPrefersTheApp() {
        let linked = todo("app edit", reminderID: "R1")
        let plan = RemindersMerge.plan(
            todos: [linked],
            remotes: [remote("R1", "remote edit")],
            snapshot: ["R1": snap("original")]
        )
        XCTAssertEqual(plan.todos.map(\.text), ["app edit"])
        XCTAssertEqual(plan.updateRemote.map(\.text), ["app edit"])
    }

    func testMissingSnapshotPrefersTheApp() {
        let linked = todo("app text", reminderID: "R1")
        let plan = RemindersMerge.plan(todos: [linked], remotes: [remote("R1", "remote text")], snapshot: [:])
        XCTAssertEqual(plan.todos.map(\.text), ["app text"])
        XCTAssertEqual(plan.updateRemote.map(\.text), ["app text"])
    }

    func testLocalDeletionRemovesReminder() {
        let plan = RemindersMerge.plan(
            todos: [],
            remotes: [remote("R1", "gone locally")],
            snapshot: ["R1": snap("gone locally")]
        )
        XCTAssertEqual(plan.deleteRemote, ["R1"])
        XCTAssertTrue(plan.todos.isEmpty)
        XCTAssertNil(plan.snapshot["R1"])
    }

    func testRemoteDeletionRemovesTodo() {
        let linked = todo("gone remotely", reminderID: "R1")
        let plan = RemindersMerge.plan(todos: [linked], remotes: [], snapshot: ["R1": snap("gone remotely")])
        XCTAssertTrue(plan.todos.isEmpty)
        XCTAssertTrue(plan.deleteRemote.isEmpty)
        XCTAssertNil(plan.snapshot["R1"])
    }

    func testLinkedTodoWithVanishedReminderAndNoSnapshotIsRecreated() {
        let linked = todo("orphan", reminderID: "R1")
        let plan = RemindersMerge.plan(todos: [linked], remotes: [], snapshot: [:])
        XCTAssertEqual(plan.createRemote, [linked.id])
        XCTAssertEqual(plan.todos.map(\.text), ["orphan"])
        XCTAssertNil(plan.todos[0].reminderID)
    }

    func testUnchangedPairProducesNoWork() {
        let linked = todo("steady", reminderID: "R1")
        let plan = RemindersMerge.plan(
            todos: [linked],
            remotes: [remote("R1", "steady")],
            snapshot: ["R1": snap("steady")]
        )
        XCTAssertTrue(plan.createRemote.isEmpty)
        XCTAssertTrue(plan.updateRemote.isEmpty)
        XCTAssertTrue(plan.deleteRemote.isEmpty)
        XCTAssertEqual(plan.todos, [linked])
    }
}
