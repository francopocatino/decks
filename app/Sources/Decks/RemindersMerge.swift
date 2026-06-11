import Foundation

// Three-way merge between a deck's to-dos and its Reminders list, against the
// state recorded at the last successful sync. Snapshot-based so edits made by
// the CLI or MCP server (which carry no modification timestamps) still sync.
// On a conflicting edit of the same item, the app wins.
enum RemindersMerge {
    struct Remote: Hashable {
        var id: String
        var text: String
        var done: Bool
        var completedAt: Date?
        var due: Date?
    }

    struct Snapshot: Codable, Hashable {
        var text: String
        var done: Bool
        var due: Date?
    }

    struct Plan {
        var todos: [Todo]
        var createRemote: [UUID]
        var updateRemote: [Remote]
        var deleteRemote: [String]
        var snapshot: [String: Snapshot]
    }

    static func plan(todos: [Todo], remotes: [Remote], snapshot: [String: Snapshot]) -> Plan {
        let remotesByID = Dictionary(remotes.map { ($0.id, $0) }) { first, _ in first }
        var result: [Todo] = []
        var createRemote: [UUID] = []
        var updateRemote: [Remote] = []
        var deleteRemote: [String] = []
        var nextSnapshot: [String: Snapshot] = [:]
        var matched: Set<String> = []

        for var todo in todos {
            guard let reminderID = todo.reminderID else {
                createRemote.append(todo.id)
                result.append(todo)
                continue
            }
            guard let remote = remotesByID[reminderID] else {
                if snapshot[reminderID] != nil { continue }
                todo.reminderID = nil
                createRemote.append(todo.id)
                result.append(todo)
                continue
            }
            matched.insert(reminderID)
            let snap = snapshot[reminderID]
            let appChanged = snap.map { todo.text != $0.text || todo.done != $0.done || todo.due != $0.due } ?? true
            let remoteChanged = snap.map { remote.text != $0.text || remote.done != $0.done || remote.due != $0.due } ?? false
            if appChanged {
                if remote.text != todo.text || remote.done != todo.done || remote.due != todo.due {
                    updateRemote.append(
                        Remote(id: reminderID, text: todo.text, done: todo.done, completedAt: todo.doneAt, due: todo.due)
                    )
                }
            } else if remoteChanged {
                todo.text = remote.text
                todo.due = remote.due
                if todo.done != remote.done {
                    todo.done = remote.done
                    todo.doneAt = remote.done ? (remote.completedAt ?? Date()) : nil
                }
            }
            nextSnapshot[reminderID] = Snapshot(text: todo.text, done: todo.done, due: todo.due)
            result.append(todo)
        }

        for remote in remotes where !matched.contains(remote.id) {
            if snapshot[remote.id] != nil {
                deleteRemote.append(remote.id)
                continue
            }
            var todo = Todo(text: remote.text)
            todo.reminderID = remote.id
            todo.due = remote.due
            if remote.done {
                todo.done = true
                todo.doneAt = remote.completedAt ?? Date()
            }
            result.insert(todo, at: 0)
            nextSnapshot[remote.id] = Snapshot(text: todo.text, done: todo.done, due: todo.due)
        }

        return Plan(
            todos: result,
            createRemote: createRemote,
            updateRemote: updateRemote,
            deleteRemote: deleteRemote,
            snapshot: nextSnapshot
        )
    }
}
