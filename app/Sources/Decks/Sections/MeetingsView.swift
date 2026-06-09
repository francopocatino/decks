import AppKit
import SwiftUI

struct MeetingsView: View {
    @Environment(IdentityStore.self) private var identity
    let slug: String

    @State private var scope: CalendarService.Scope = .today
    @State private var meetings: [Meeting] = []
    @State private var authorized = CalendarService.isAuthorized()
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task(id: scope) { await load() }
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
        if !authorized {
            ContentUnavailableView {
                Label("Calendar access", systemImage: "calendar")
            } description: {
                Text("Allow calendar access to see this deck's meetings.")
            } actions: {
                Button("Allow access") {
                    Task {
                        await CalendarService.requestAccess()
                        authorized = CalendarService.isAuthorized()
                        await load()
                    }
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
            List(meetings) { meeting in
                row(meeting)
            }
            .listStyle(.inset)
        }
    }

    private func row(_ meeting: Meeting) -> some View {
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
        .padding(.vertical, 2)
    }

    private func timeLabel(_ meeting: Meeting) -> String {
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        if scope == .today || Calendar.current.isDateInToday(meeting.start) {
            return time
        }
        let day = meeting.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) · \(time)"
    }

    private func load() async {
        loading = true
        meetings = await CalendarService.meetings(
            sources: identity.profile(slug).calendarSources ?? [],
            scope: scope
        )
        authorized = CalendarService.isAuthorized()
        loading = false
    }
}
