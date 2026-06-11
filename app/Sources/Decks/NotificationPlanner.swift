import Foundation

struct PlannedNotification: Hashable {
    var id: String
    var title: String
    var body: String
    var fireDate: Date
    var url: String?
}

// Builds the set of notifications that should be pending right now: today's
// upcoming meetings (lead minutes before the start) and open to-dos with a
// future due date. Pure, so the scheduling policy is unit-testable.
enum NotificationPlanner {
    static let limit = 60

    static func plan(
        meetings: [Meeting],
        todos: [(deck: String, todo: Todo)],
        leadMinutes: Int,
        now: Date
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        var seen: Set<String> = []

        for meeting in meetings {
            let fireDate = meeting.start.addingTimeInterval(-Double(leadMinutes) * 60)
            guard fireDate > now, seen.insert(meeting.id).inserted else { continue }
            planned.append(
                PlannedNotification(
                    id: "meeting-\(meeting.id)",
                    title: meeting.title,
                    body: "Starts at \(meeting.start.formatted(date: .omitted, time: .shortened))",
                    fireDate: fireDate,
                    url: meeting.link?.absoluteString
                )
            )
        }

        for (deck, todo) in todos {
            guard !todo.done, let due = todo.due, due > now else { continue }
            planned.append(
                PlannedNotification(
                    id: "todo-\(todo.id.uuidString)",
                    title: todo.text,
                    body: "Due now · \(deck)",
                    fireDate: due,
                    url: nil
                )
            )
        }

        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
