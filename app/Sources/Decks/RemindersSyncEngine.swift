import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class RemindersSyncEngine {
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private let identity: IdentityStore
    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var dirty = true
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var lastSync = Date.distantPast

    init(store: DecksStore, identity: IdentityStore) {
        self.store = store
        self.identity = identity
        store.onTodosChanged = { [weak self] _ in self?.dirty = true }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dirty = true }
        }
    }

    static func isAuthorized() -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: true
        default: false
        }
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        if isAuthorized() { return true }
        return (try? await EKEventStore().requestFullAccessToReminders()) ?? false
    }

    func tick() async {
        guard !syncing else { return }
        guard dirty || Date().timeIntervalSince(lastSync) > 5 else { return }
        guard Self.isAuthorized() else { return }
        syncing = true
        defer { syncing = false }
        dirty = false
        lastSync = Date()
        for deck in store.visibleDecks where identity.profile(deck.slug).remindersSync == true {
            await sync(deck)
        }
    }

    private func sync(_ deck: Deck) async {
        guard let calendar = ensureCalendar(for: deck) else { return }
        let reminders = await fetchReminders(in: calendar)
        let remotes = reminders.compactMap { reminder -> RemindersMerge.Remote? in
            let text = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RemindersMerge.Remote(
                id: reminder.calendarItemIdentifier,
                text: text,
                done: reminder.isCompleted,
                completedAt: reminder.completionDate,
                due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            )
        }

        let snapshotURL = Storage.deckDirectory(deck.slug).appendingPathComponent("reminders-sync.json")
        let snapshot = Storage.readJSON([String: RemindersMerge.Snapshot].self, at: snapshotURL) ?? [:]
        var plan = RemindersMerge.plan(todos: store.todos(deck.slug), remotes: remotes, snapshot: snapshot)

        let remindersByID = Dictionary(reminders.map { ($0.calendarItemIdentifier, $0) }) { first, _ in first }
        for update in plan.updateRemote {
            guard let reminder = remindersByID[update.id] else { continue }
            reminder.title = update.text
            reminder.isCompleted = update.done
            if update.done { reminder.completionDate = update.completedAt ?? Date() }
            let currentDue = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            if currentDue != update.due { setDue(update.due, on: reminder) }
            try? eventStore.save(reminder, commit: false)
        }
        for id in plan.deleteRemote {
            guard let reminder = remindersByID[id] else { continue }
            try? eventStore.remove(reminder, commit: false)
        }
        for todoID in plan.createRemote {
            guard let index = plan.todos.firstIndex(where: { $0.id == todoID }) else { continue }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = plan.todos[index].text
            reminder.isCompleted = plan.todos[index].done
            if plan.todos[index].done { reminder.completionDate = plan.todos[index].doneAt ?? Date() }
            setDue(plan.todos[index].due, on: reminder)
            guard (try? eventStore.save(reminder, commit: false)) != nil else { continue }
            plan.todos[index].reminderID = reminder.calendarItemIdentifier
            plan.snapshot[reminder.calendarItemIdentifier] = RemindersMerge.Snapshot(
                text: plan.todos[index].text,
                done: plan.todos[index].done,
                due: plan.todos[index].due
            )
        }
        try? eventStore.commit()

        if plan.todos != store.todos(deck.slug) {
            store.replaceTodos(plan.todos, for: deck.slug)
        }
        if plan.snapshot != snapshot {
            Storage.writeJSON(plan.snapshot, to: snapshotURL)
        }
    }

    private func setDue(_ due: Date?, on reminder: EKReminder) {
        reminder.dueDateComponents = due.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        reminder.alarms = due.map { [EKAlarm(absoluteDate: $0)] }
    }

    private func ensureCalendar(for deck: Deck) -> EKCalendar? {
        var profile = identity.profile(deck.slug)
        if let id = profile.remindersCalendarID, let calendar = eventStore.calendar(withIdentifier: id) {
            return calendar
        }
        let calendar: EKCalendar
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == deck.name }) {
            calendar = existing
        } else {
            let created = EKCalendar(for: .reminder, eventStore: eventStore)
            created.title = deck.name
            guard let source = eventStore.defaultCalendarForNewReminders()?.source
                ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
                ?? eventStore.sources.first(where: { $0.sourceType == .local })
            else { return nil }
            created.source = source
            guard (try? eventStore.saveCalendar(created, commit: true)) != nil else { return nil }
            calendar = created
        }
        profile.remindersCalendarID = calendar.calendarIdentifier
        identity.saveProfile(profile, for: deck.slug)
        return calendar
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let ids: [String] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(\.calendarItemIdentifier))
            }
        }
        return ids.compactMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
    }
}
