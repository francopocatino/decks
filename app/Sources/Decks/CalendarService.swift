import EventKit
import Foundation

enum CalendarService {
    enum Outcome {
        case added([String])
        case noEvents
        case denied
    }

    static func todayMeetings() async -> Outcome {
        let store = EKEventStore()
        guard await ensureAccess(store) else { return .denied }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .noEvents }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let lines = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(format)
        return lines.isEmpty ? .noEvents : .added(lines)
    }

    private static func ensureAccess(_ store: EKEventStore) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    private static func format(_ event: EKEvent) -> String {
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        let title = event.title ?? "Untitled"
        if let link = meetLink(event) {
            return "- \(time) \(title) — \(link)"
        }
        return "- \(time) \(title)"
    }

    private static func meetLink(_ event: EKEvent) -> String? {
        if let url = event.url?.absoluteString, url.hasPrefix("http") {
            return url
        }
        for text in [event.notes, event.location].compactMap({ $0 }) {
            if let range = text.range(
                of: #"https?://meet\.google\.com/[^\s>]+"#,
                options: .regularExpression
            ) {
                return String(text[range])
            }
        }
        return nil
    }
}
