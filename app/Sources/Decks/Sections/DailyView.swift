import SwiftUI

struct DailyView: View {
    @Environment(DecksStore.self) private var store
    let slug: String

    var body: some View {
        TextEditor(text: dailyBinding)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.appendDailyEntry(to: slug)
                    } label: {
                        Label("Today", systemImage: "calendar.badge.plus")
                    }
                }
            }
    }

    private var dailyBinding: Binding<String> {
        Binding(
            get: { store.daily(slug) },
            set: { store.setDaily($0, for: slug) }
        )
    }
}
