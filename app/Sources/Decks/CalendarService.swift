import EventKit
import Foundation

struct CalendarAccount: Identifiable, Hashable {
    let id: String
    let title: String
}

enum CalendarService {
    enum Outcome {
        case added([String])
        case noEvents
        case denied
    }

    static func isAuthorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: true
        default: false
        }
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        if isAuthorized() { return true }
        let store = EKEventStore()
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func accounts() async -> [CalendarAccount] {
        guard isAuthorized() else { return [] }
        let store = EKEventStore()
        var seen = Set<String>()
        var result: [CalendarAccount] = []
        for source in store.calendars(for: .event).compactMap(\.source) {
            if seen.insert(source.sourceIdentifier).inserted {
                result.append(CalendarAccount(id: source.sourceIdentifier, title: source.title))
            }
        }
        return result.sorted { $0.title < $1.title }
    }

    static func todayMeetings(sources: [String]) async -> Outcome {
        let store = EKEventStore()
        guard await requestAccess() else { return .denied }

        let all = store.calendars(for: .event)
        let calendars = sources.isEmpty ? all : all.filter { sources.contains($0.source?.sourceIdentifier ?? "") }
        guard !calendars.isEmpty else { return .noEvents }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .noEvents }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let lines = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map(format)
        return lines.isEmpty ? .noEvents : .added(lines)
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
