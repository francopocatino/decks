import AppKit
import SwiftUI

// A launchpad across every deck: a full cross-deck meeting agenda on top, then
// one pulse card per context (open/overdue to-dos, time today, next meeting,
// latest daily line) so you can survey everything and jump into the right one.
struct TodayView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    @Environment(TimeTrackingEngine.self) private var tracker
    var onOpenDeck: (String) -> Void = { _ in }

    @State private var meetingsByDeck: [String: [Meeting]] = [:]
    @State private var scope: CalendarService.Scope = .today
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                agenda
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(store.topLevelVisibleDecks()) { deck in
                        card(deck)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Today")
        .task(id: reloadKey) { await load() }
        .onReceive(tick) { value in
            now = value
            Task { await load() }
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AGENDA")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $scope) {
                    Text("Today").tag(CalendarService.Scope.today)
                    Text("Upcoming").tag(CalendarService.Scope.upcoming)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }

            if agendaItems.isEmpty {
                Text(emptyAgendaHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedAgenda, id: \.day) { group in
                        if showDayHeaders {
                            Text(dayLabel(group.day))
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, group.day == groupedAgenda.first?.day ? 4 : 16)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.items) { item in
                            agendaRow(item)
                            // In Today's flat list dividers aid scanning; under
                            // day headers they just clutter, so drop them there.
                            if !showDayHeaders, item.id != group.items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func agendaRow(_ item: AgendaItem) -> some View {
        HStack(spacing: 10) {
            Text(item.meeting.start.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            DeckIcon(deck: item.deck, accent: store.accent(for: item.deck))
            Text(item.meeting.title).lineLimit(1)
            Spacer()
            if let link = item.meeting.link {
                Button("Join") { NSWorkspace.shared.open(link) }
            }
        }
        .opacity(item.meeting.end < now ? 0.5 : 1)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDeck(item.deck.slug) }
    }

    private struct AgendaItem: Identifiable {
        let meeting: Meeting
        let deck: Deck
        var id: String { meeting.id }
    }

    // Deduped across decks (a shared calendar is attributed to the first deck
    // that lists it), sorted by start.
    private var agendaItems: [AgendaItem] {
        var seen: Set<String> = []
        var items: [AgendaItem] = []
        for deck in store.topLevelVisibleDecks() {
            for meeting in meetingsByDeck[deck.slug] ?? [] where seen.insert(meeting.id).inserted {
                items.append(AgendaItem(meeting: meeting, deck: deck))
            }
        }
        return items.sorted { $0.meeting.start < $1.meeting.start }
    }

    // Upcoming spans several days; group under day headers so identical
    // recurring slots read as different days, not duplicates.
    private var groupedAgenda: [(day: Date, items: [AgendaItem])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: agendaItems) { calendar.startOfDay(for: $0.meeting.start) }
        return groups.keys.sorted().map { day in
            (day: day, items: groups[day]!.sorted { $0.meeting.start < $1.meeting.start })
        }
    }

    private var showDayHeaders: Bool { scope == .upcoming }

    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private var emptyAgendaHint: String {
        if !hasSources { return "No calendars selected on any deck — choose them in a deck's Settings." }
        return scope == .today ? "Nothing on your calendars today." : "Nothing coming up."
    }

    private var hasSources: Bool {
        store.topLevelVisibleDecks().contains {
            !identity.effectiveCalendarSources(for: $0.slug, parent: $0.parent).isEmpty
        }
    }

    // MARK: Deck card

    private func card(_ deck: Deck) -> some View {
        let open = store.openTodoCount(deck.slug)
        let overdue = overdueCount(deck.slug)
        let time = tracker.ledger(deck.slug).seconds(on: TimeLedger.day(now))
        let next = nextMeeting(deck.slug)
        let daily = latestDailyLine(deck.slug)
        let accent = store.accentTint(for: deck)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                DeckIcon(deck: deck, accent: store.accent(for: deck))
                Text(deck.name).font(.headline)
                Spacer()
                if time > 0 {
                    Text(TimeView.label(time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label("\(open)", systemImage: "checklist")
                    .foregroundStyle(open > 0 ? .primary : .secondary)
                if overdue > 0 {
                    Label("\(overdue) overdue", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                if let next {
                    Label(next.start.formatted(date: .omitted, time: .shortened), systemImage: "person.2")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let next {
                Text(next.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let daily {
                Text(daily).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((accent ?? .secondary).opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenDeck(deck.slug) }
    }

    // MARK: Data

    private func overdueCount(_ slug: String) -> Int {
        store.todos(slug).filter { !$0.done && ($0.due.map { $0 < now } ?? false) }.count
    }

    private func nextMeeting(_ slug: String) -> Meeting? {
        (meetingsByDeck[slug] ?? [])
            .filter { $0.end >= now }
            .min { $0.start < $1.start }
    }

    private func latestDailyLine(_ slug: String) -> String? {
        for raw in store.daily(slug).split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            return line.replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
        }
        return nil
    }

    // Refetch when the scope, the set of decks, or their calendar selection changes.
    private var reloadKey: String {
        let scopeKey = scope == .today ? "today" : "upcoming"
        let decks = store.topLevelVisibleDecks()
            .map { "\($0.slug):\(identity.effectiveCalendarSources(for: $0.slug, parent: $0.parent).sorted().joined(separator: "+"))" }
            .joined(separator: ",")
        return "\(scopeKey)|\(decks)"
    }

    private func load() async {
        var result: [String: [Meeting]] = [:]
        for deck in store.topLevelVisibleDecks() {
            let sources = identity.effectiveCalendarSources(for: deck.slug, parent: deck.parent)
            guard !sources.isEmpty else { continue }
            result[deck.slug] = await CalendarService.meetings(sources: sources, scope: scope)
        }
        meetingsByDeck = result
    }
}
