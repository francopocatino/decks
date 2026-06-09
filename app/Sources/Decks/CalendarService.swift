import EventKit
import Foundation

enum CalendarService {
    static func todayMeetings() async -> [String] {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let time = event.startDate.formatted(date: .omitted, time: .shortened)
                return "- \(time) \(event.title ?? "Untitled")"
            }
    }
}
