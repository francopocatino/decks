import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationScheduler {
    static let meetingCategory = "decks.meeting"
    static let joinAction = "decks.join"

    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private let identity: IdentityStore
    @ObservationIgnored private var lastPlanned: [PlannedNotification]?
    @ObservationIgnored private var submitted: Set<String> = []
    @ObservationIgnored private var throttle = Throttle(60)

    // UNUserNotificationCenter aborts outside a real .app bundle (swift run, tests).
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    init(store: DecksStore, identity: IdentityStore) {
        self.store = store
        self.identity = identity
        guard Self.isSupported else { return }
        let join = UNNotificationAction(identifier: Self.joinAction, title: "Join", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.meetingCategory,
            actions: [join],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @discardableResult
    static func requestAccess() async -> Bool {
        guard isSupported else { return false }
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    func tick() async {
        guard Self.isSupported else { return }
        guard throttle.ready() else { return }

        let defaults = UserDefaults.standard
        let meetingAlerts = defaults.bool(forKey: Pref.meetingAlerts)
        let dueAlerts = defaults.bool(forKey: Pref.dueAlerts)
        guard meetingAlerts || dueAlerts else {
            if lastPlanned?.isEmpty == false {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            }
            lastPlanned = []
            return
        }

        var meetings: [Meeting] = []
        if meetingAlerts, CalendarService.isAuthorized() {
            var sources: Set<String> = []
            for deck in store.visibleDecks {
                sources.formUnion(identity.effectiveCalendarSources(for: deck.slug, parent: deck.parent))
            }
            meetings = await CalendarService.meetings(sources: Array(sources), scope: .today)
        }
        let todos: [(deck: String, todo: Todo)] = dueAlerts
            ? store.visibleDecks.flatMap { deck in store.todos(deck.slug).map { (deck.name, $0) } }
            : []

        let lead = defaults.object(forKey: Pref.meetingAlertLead) as? Int ?? 2
        let planned = NotificationPlanner.plan(meetings: meetings, todos: todos, leadMinutes: lead, now: Date())
        guard planned != lastPlanned else { return }
        lastPlanned = planned

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for item in planned {
            // Past-dated items (already inside the lead window) fire once,
            // immediately; never resubmit them on later plan rebuilds.
            if item.fireDate <= Date(), submitted.contains(item.id) { continue }
            submitted.insert(item.id)
            center.add(request(for: item), withCompletionHandler: nil)
        }
    }

    private func request(for planned: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        if let url = planned.url {
            content.categoryIdentifier = Self.meetingCategory
            content.userInfo = ["url": url]
        }
        let trigger: UNNotificationTrigger
        if planned.fireDate <= Date() {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: planned.fireDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }
}
