import AppKit
import SwiftUI

struct MeetingsView: View {
    @Environment(IdentityStore.self) private var identity
    @Environment(DecksStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    let slug: String

    @State private var scope: CalendarService.Scope = .today
    @State private var meetings: [Meeting] = []
    // Optimistic: load() sets the real value from requestAccess() (the
    // authoritative check). Starting false here would flash the access prompt
    // on every deck switch when EKEventStore's cached status is stale.
    @State private var authorized = true
    @State private var loading = true
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task(id: reloadKey) { await load() }
        .onReceive(tick) { instant in
            now = instant
            // Refetch on the timer so the list isn't frozen across midnight or
            // after an external calendar edit (the 'meetings' array is otherwise
            // only rebuilt on scope/source change or a manual refresh).
            Task { await load() }
        }
    }

    private var sources: [String] {
        identity.effectiveCalendarSources(for: slug, parent: store.deck(slug)?.parent)
    }

    // Reloads whenever the scope or the deck's calendar sources change.
    private var reloadKey: String {
        "\(scope == .today ? "today" : "all")|\(sources.sorted().joined(separator: ","))"
    }

    private var header: some View {
        HStack {
            Picker("", selection: $scope) {
                Text("Today").tag(CalendarService.Scope.today)
                Text("All").tag(CalendarService.Scope.upcoming)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            ContentUnavailableView {
                Label("No calendar selected", systemImage: "calendar")
            } description: {
                Text("Choose which calendar account this deck reads from.")
            } actions: {
                Button("Open settings", action: openDeckSettings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !authorized {
            ContentUnavailableView {
                Label("Calendar access", systemImage: "calendar")
            } description: {
                Text("Allow calendar access to see this deck's meetings.")
            } actions: {
                Button("Allow access") {
                    Task { await load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if meetings.isEmpty {
            ContentUnavailableView(
                loading ? "Loading…" : "No meetings",
                systemImage: "person.2",
                description: Text(scope == .today ? "Nothing on this deck's calendars today." : "Nothing coming up.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(rows) { row in
                switch row {
                case .now: nowLine
                case let .meeting(meeting): meetingRow(meeting)
                }
            }
            .listStyle(.inset)
        }
    }

    private enum Row: Identifiable {
        case now
        case meeting(Meeting)

        var id: String {
            switch self {
            case .now: "now-marker"
            case let .meeting(meeting): meeting.id
            }
        }
    }

    private var rows: [Row] {
        let hasPast = meetings.contains { $0.end < now }
        let hasUpcoming = meetings.contains { $0.end >= now }
        var result: [Row] = []
        var insertedNow = false
        for meeting in meetings {
            if hasPast, hasUpcoming, !insertedNow, meeting.end >= now {
                result.append(.now)
                insertedNow = true
            }
            result.append(.meeting(meeting))
        }
        return result
    }

    private var nowLine: some View {
        HStack(spacing: 8) {
            Text("Now")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
            Rectangle()
                .fill(.red.opacity(0.7))
                .frame(height: 1)
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                Text(timeLabel(meeting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let link = meeting.link {
                Button("Join") { NSWorkspace.shared.open(link) }
            }
        }
        .opacity(meeting.end < now ? 0.45 : 1)
        .padding(.vertical, 2)
    }

    private func timeLabel(_ meeting: Meeting) -> String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(meeting.start) {
            return time
        }
        let day = meeting.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) · \(time)"
    }

    private func openDeckSettings() {
        store.settingsDeck = slug
        store.settingsSection = .decks
        openSettings()
    }

    private func load() async {
        let requested = reloadKey
        // No calendar selected: nothing to authorize or fetch, and asking for
        // calendar access here would prompt decks that never opted in.
        guard !sources.isEmpty else {
            meetings = []
            loading = false
            return
        }
        loading = true
        // requestAccess() is authoritative — it reports access granted even
        // when EKEventStore's cached authorizationStatus is briefly stale, so
        // the prompt resolves on its own instead of needing a click per switch.
        let granted = await CalendarService.requestAccess()
        let fetched = granted ? await CalendarService.meetings(sources: sources, scope: scope) : []
        // A newer scope/source supersedes this fetch: drop its stale result.
        guard !Task.isCancelled, requested == reloadKey else { return }
        authorized = granted
        meetings = fetched
        loading = false
    }
}
