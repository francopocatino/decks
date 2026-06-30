import AppKit
import SwiftUI

// A cross-deck landing view: what's due, what's on the calendar, and how much
// context time today — pulled from every visible deck into one place.
struct TodayView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    @Environment(TimeTrackingEngine.self) private var tracker
    var onOpenDeck: (String) -> Void = { _ in }

    @State private var meetings: [Meeting] = []
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summary
                if !dueItems.isEmpty { dueSection }
                if !meetings.isEmpty { meetingsSection }
                if dueItems.isEmpty, meetings.isEmpty { clearHint }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Today")
        .task(id: sourcesKey) { await loadMeetings() }
        .onReceive(tick) { value in
            now = value
            Task { await loadMeetings() }
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 28) {
            stat("Time today", TimeView.label(timeToday))
            stat("Due", "\(dueItems.count)")
            stat("Meetings", "\(meetings.count)")
            Spacer()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: Due

    private struct DueItem: Identifiable {
        let id: UUID
        let deck: Deck
        let text: String
        let due: Date
        let overdue: Bool
    }

    private var dueItems: [DueItem] {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        var items: [DueItem] = []
        for deck in store.visibleDecks {
            for todo in store.todos(deck.slug) where !todo.done {
                guard let due = todo.due, due <= endOfToday else { continue }
                items.append(DueItem(id: todo.id, deck: deck, text: todo.text, due: due, overdue: due < now))
            }
        }
        return items.sorted { $0.due < $1.due }
    }

    private var dueSection: some View {
        section("Due & overdue") {
            ForEach(dueItems) { item in
                dueRow(item)
                if item.id != dueItems.last?.id { Divider() }
            }
        }
    }

    private func dueRow(_ item: DueItem) -> some View {
        HStack(spacing: 10) {
            Button { store.toggleTodo(item.id, in: item.deck.slug) } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                HStack(spacing: 5) {
                    DeckIcon(deck: item.deck, accent: store.accent(for: item.deck))
                    Text(item.deck.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(dueLabel(item))
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.overdue ? .red : .secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDeck(item.deck.slug) }
    }

    private func dueLabel(_ item: DueItem) -> String {
        let time = item.due.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(item.due) { return time }
        if item.overdue { return "Overdue · \(item.due.formatted(.dateTime.day().month(.abbreviated)))" }
        return "\(item.due.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
    }

    // MARK: Meetings

    private var meetingsSection: some View {
        section("Meetings today") {
            ForEach(meetings) { meeting in
                meetingRow(meeting)
                if meeting.id != meetings.last?.id { Divider() }
            }
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Text(meeting.start.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(meeting.title)
            Spacer()
            if let link = meeting.link {
                Button("Join") { NSWorkspace.shared.open(link) }
            }
        }
        .opacity(meeting.end < now ? 0.5 : 1)
        .padding(.vertical, 6)
    }

    // MARK: Empty

    private var clearHint: some View {
        ContentUnavailableView(
            "Clear for today",
            systemImage: "checkmark.circle",
            description: Text("Nothing due and no meetings on your decks' calendars.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
        }
    }

    private var sources: [String] {
        var set: Set<String> = []
        for deck in store.visibleDecks {
            set.formUnion(identity.effectiveCalendarSources(for: deck.slug, parent: deck.parent))
        }
        return Array(set).sorted()
    }

    private var sourcesKey: String { sources.joined(separator: ",") }

    private var timeToday: TimeInterval {
        let day = TimeLedger.day(now)
        return store.visibleDecks.reduce(0) { $0 + tracker.ledger($1.slug).seconds(on: day) }
    }

    private func loadMeetings() async {
        let current = sources
        guard !current.isEmpty else {
            meetings = []
            return
        }
        meetings = await CalendarService.meetings(sources: current, scope: .today)
    }
}
