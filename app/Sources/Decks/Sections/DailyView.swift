import AppKit
import SwiftUI

struct DailyView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var preview = false
    @State private var noMeetings = false
    @State private var accessDenied = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if preview {
                ScrollView {
                    MarkdownView(text: store.daily(slug))
                        .padding(16)
                }
            } else {
                TextEditor(text: dailyBinding)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
        }
        .alert("No meetings today", isPresented: $noMeetings) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing with a time on your calendars for today.")
        }
        .alert("Calendar access needed", isPresented: $accessDenied) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Calendar access for Decks in System Settings → Privacy & Security → Calendars.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                store.appendDailyEntry(to: slug)
            } label: {
                Label("Today", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)

            Button(action: addMeetings) {
                Label("Meetings", systemImage: "calendar.badge.clock")
            }
            .buttonStyle(.borderless)
            .help("Add today's calendar events to the daily")

            Spacer()

            if !store.daily(slug).isEmpty {
                Button(action: copyToday) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy today's entry to the clipboard")
            }

            Picker("", selection: $preview) {
                Image(systemName: "pencil").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var dailyBinding: Binding<String> {
        Binding(
            get: { store.daily(slug) },
            set: { store.setDaily($0, for: slug) }
        )
    }

    private func addMeetings() {
        Task {
            switch await CalendarService.todayMeetings() {
            case let .added(lines):
                store.addDailyLine("### Meetings\n\n" + lines.joined(separator: "\n"), to: slug)
            case .noEvents:
                noMeetings = true
            case .denied:
                accessDenied = true
            }
        }
    }

    private func copyToday() {
        let daily = store.daily(slug)
        let header = "## \(DecksStore.dailyDate())"
        let block: String
        if daily.hasPrefix(header) {
            let afterHeader = daily.index(daily.startIndex, offsetBy: header.count)
            if let next = daily.range(of: "\n## ", range: afterHeader ..< daily.endIndex) {
                block = String(daily[..<next.lowerBound])
            } else {
                block = daily
            }
        } else {
            block = daily
        }
        let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
