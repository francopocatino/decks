import AppKit
import SwiftUI

// A launchpad across every deck: one card per context showing its pulse —
// open and overdue to-dos, time today, next meeting, the latest daily line —
// so you can survey all your contexts and jump into the right one.
struct TodayView: View {
    @Environment(DecksStore.self) private var store
    @Environment(IdentityStore.self) private var identity
    @Environment(TimeTrackingEngine.self) private var tracker
    var onOpenDeck: (String) -> Void = { _ in }

    @State private var meetingsByDeck: [String: [Meeting]] = [:]
    @State private var now = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !upcoming.isEmpty { upcomingStrip }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(store.topLevelVisibleDecks()) { deck in
                        card(deck)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Today")
        .task(id: deckSignature) { await load() }
        .onReceive(tick) { value in
            now = value
            Task { await load() }
        }
    }

    // MARK: Up next

    private var upcomingStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UP NEXT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(upcoming.prefix(3))) { meeting in
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
                    .padding(.vertical, 6)
                    if meeting.id != upcoming.prefix(3).last?.id { Divider() }
                }
            }
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

    private var upcoming: [Meeting] {
        var seen: Set<String> = []
        return meetingsByDeck.values
            .flatMap { $0 }
            .filter { $0.end >= now && seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    private func latestDailyLine(_ slug: String) -> String? {
        for raw in store.daily(slug).split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            return line.replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
        }
        return nil
    }

    // Refetch when the set of decks or their calendar selection changes.
    private var deckSignature: String {
        store.topLevelVisibleDecks()
            .map { "\($0.slug):\(identity.effectiveCalendarSources(for: $0.slug, parent: $0.parent).sorted().joined(separator: "+"))" }
            .joined(separator: ",")
    }

    private func load() async {
        var result: [String: [Meeting]] = [:]
        for deck in store.topLevelVisibleDecks() {
            let sources = identity.effectiveCalendarSources(for: deck.slug, parent: deck.parent)
            guard !sources.isEmpty else { continue }
            result[deck.slug] = await CalendarService.meetings(sources: sources, scope: .today)
        }
        meetingsByDeck = result
    }
}
