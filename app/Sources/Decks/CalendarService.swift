import EventKit
import Foundation

struct CalendarAccount: Identifiable, Hashable {
    let id: String
    let title: String
}

struct Meeting: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let link: URL?
}

enum CalendarService {
    enum Scope {
        case today, upcoming
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
        var titles: [String: String] = [:]
        var emails: [String: String] = [:]
        for calendar in store.calendars(for: .event) {
            guard let source = calendar.source else { continue }
            let id = source.sourceIdentifier
            titles[id] = source.title
            if emails[id] == nil, calendar.title.contains("@") {
                emails[id] = calendar.title
            }
        }
        return titles.map { id, title in
            let display = title.contains("@") ? title : (emails[id] ?? title)
            return CalendarAccount(id: id, title: display)
        }
        .sorted { $0.title < $1.title }
    }

    static func meetings(sources: [String], scope: Scope) async -> [Meeting] {
        guard !sources.isEmpty else { return [] }
        let store = EKEventStore()
        guard await requestAccess() else { return [] }

        let calendars = store.calendars(for: .event)
            .filter { sources.contains($0.source?.sourceIdentifier ?? "") }
        guard !calendars.isEmpty else { return [] }

        let calendar = Calendar.current
        let start: Date
        let end: Date
        switch scope {
        case .today:
            start = calendar.startOfDay(for: Date())
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .upcoming:
            start = Date()
            end = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: start)) ?? start
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Meeting(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    link: meetLink(event)
                )
            }
    }

    @discardableResult
    static func createTimeBlock(
        title: String,
        start: Date,
        duration: TimeInterval,
        sources: [String],
        note: String
    ) async -> Bool {
        guard await requestAccess() else { return false }
        let store = EKEventStore()
        let scoped = store.calendars(for: .event)
            .filter { sources.contains($0.source?.sourceIdentifier ?? "") && $0.allowsContentModifications }
        guard let calendar = scoped.first ?? store.defaultCalendarForNewEvents else { return false }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration)
        event.notes = note
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    private static func meetLink(_ event: EKEvent) -> URL? {
        guard let raw = rawMeetLink(event) else { return nil }
        if raw.contains("meet.google.com"),
           let email = accountEmail(event.calendar),
           var components = URLComponents(string: raw) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "authuser", value: email))
            components.queryItems = items
            return components.url ?? URL(string: raw)
        }
        return URL(string: raw)
    }

    private static func rawMeetLink(_ event: EKEvent) -> String? {
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

    private static func accountEmail(_ calendar: EKCalendar?) -> String? {
        guard let title = calendar?.source?.title, title.contains("@") else { return nil }
        return title
    }
}
