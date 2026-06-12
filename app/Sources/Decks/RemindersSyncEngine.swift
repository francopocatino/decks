import EventKit
import Foundation
import Observation

// Sync state lives next to the deck (reminders-sync.json): the linked list's
// identifier plus the per-reminder snapshot of the last successful sync. The
// engine is the only writer, so nothing the Settings form saves can clobber it.
struct RemindersSyncState: Codable {
    var calendarID: String?
    var items: [String: RemindersMerge.Snapshot]

    init(calendarID: String? = nil, items: [String: RemindersMerge.Snapshot] = [:]) {
        self.calendarID = calendarID
        self.items = items
    }
}

@MainActor
@Observable
final class RemindersSyncEngine {
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private let identity: IdentityStore
    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var dirty = true
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var throttle = Throttle(30)

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
        let due = throttle.ready()
        guard dirty || due else { return }
        guard Self.isAuthorized() else { return }
        syncing = true
        defer { syncing = false }
        dirty = false
        for deck in store.visibleDecks where identity.profile(deck.slug).remindersSync == true {
            await sync(deck)
        }
    }

    // The deck is being deleted: remove its Reminders list so it doesn't
    // get adopted (old reminders included) by a future same-named deck.
    func deckRemoved(_ slug: String) {
        guard Self.isAuthorized() else { return }
        let state = Self.readState(Self.stateURL(slug))
        guard let id = state.calendarID, let calendar = eventStore.calendar(withIdentifier: id) else { return }
        try? eventStore.removeCalendar(calendar, commit: true)
    }

    private func sync(_ deck: Deck) async {
        let stateURL = Self.stateURL(deck.slug)
        var state = Self.readState(stateURL)
        guard let calendar = ensureCalendar(for: deck, state: &state) else { return }

        let remotes = await fetchRemotes(in: calendar)

        // Re-read disk before planning so a CLI write during the await above
        // is merged instead of overwritten. Everything below is synchronous.
        store.reloadIfChanged()
        guard store.deck(deck.slug) != nil else { return }
        let todos = store.todos(deck.slug)
        var plan = RemindersMerge.plan(todos: todos, remotes: remotes, snapshot: state.items)

        for update in plan.updateRemote {
            guard let reminder = eventStore.calendarItem(withIdentifier: update.id) as? EKReminder else { continue }
            reminder.title = update.text
            reminder.isCompleted = update.done
            if update.done { reminder.completionDate = update.completedAt ?? Date() }
            let currentDue = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            if currentDue != update.due { setDue(update.due, on: reminder) }
            try? eventStore.save(reminder, commit: false)
        }
        for id in plan.deleteRemote {
            guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { continue }
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

        if plan.todos != todos {
            store.replaceTodos(plan.todos, for: deck.slug)
        }
        if plan.snapshot != state.items || state.calendarID != calendar.calendarIdentifier {
            state.items = plan.snapshot
            state.calendarID = calendar.calendarIdentifier
            Storage.writeJSON(state, to: stateURL)
        }
    }

    private func setDue(_ due: Date?, on reminder: EKReminder) {
        reminder.dueDateComponents = due.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        reminder.alarms = due.map { [EKAlarm(absoluteDate: $0)] }
    }

    private func ensureCalendar(for deck: Deck, state: inout RemindersSyncState) -> EKCalendar? {
        if let id = state.calendarID {
            if let calendar = eventStore.calendar(withIdentifier: id) {
                return calendar
            }
            // The linked list is gone (deleted or recreated in Reminders).
            // Re-link instead of letting the snapshot delete every todo:
            // with an empty snapshot the merge recreates the reminders.
            state.calendarID = nil
            state.items = [:]
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
            // A brand-new list has synced nothing; a stale snapshot here
            // would read as mass remote deletion.
            state.items = [:]
        }
        state.calendarID = calendar.calendarIdentifier
        return calendar
    }

    // Extract plain values inside the callback: one fetch, no per-item
    // EventKit lookups, nothing non-Sendable crossing the continuation.
    private func fetchRemotes(in calendar: EKCalendar) async -> [RemindersMerge.Remote] {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let remotes = (reminders ?? []).compactMap { reminder -> RemindersMerge.Remote? in
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
                continuation.resume(returning: remotes)
            }
        }
    }

    private static func stateURL(_ slug: String) -> URL {
        Storage.deckDirectory(slug).appendingPathComponent("reminders-sync.json")
    }

    // Reads the current shape, falling back to the legacy bare-snapshot
    // dictionary without tripping Storage's corrupt-file backup.
    private static func readState(_ url: URL) -> RemindersSyncState {
        guard let data = try? Data(contentsOf: url) else { return RemindersSyncState() }
        if let state = try? Storage.decoder.decode(RemindersSyncState.self, from: data) {
            return state
        }
        if let legacy = try? Storage.decoder.decode([String: RemindersMerge.Snapshot].self, from: data) {
            return RemindersSyncState(items: legacy)
        }
        return RemindersSyncState()
    }
}
