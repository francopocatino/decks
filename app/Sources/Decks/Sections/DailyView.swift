import AppKit
import SwiftUI

struct DailyView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var preview = false

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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                store.appendDailyEntry(to: slug)
            } label: {
                Label("Today", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderless)

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
