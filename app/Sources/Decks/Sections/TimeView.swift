import SwiftUI

struct TimeView: View {
    @Environment(TimeTrackingEngine.self) private var tracker
    let slug: String

    var body: some View {
        let ledger = tracker.ledger(slug)
        let days = TimeLedger.recentDays(14)
        let today = ledger.seconds(on: days[0])
        let week = ledger.total(over: Array(days.prefix(7)))

        return VStack(spacing: 0) {
            HStack(spacing: 24) {
                summary("Today", seconds: today)
                summary("Last 7 days", seconds: week)
                Spacer()
            }
            .padding(16)
            Divider()
            if ledger.total(over: days) == 0 {
                ContentUnavailableView(
                    "No time yet",
                    systemImage: "clock",
                    description: Text("Time accrues while this deck is active and you're at the keyboard.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dayList(ledger: ledger, days: days)
            }
        }
    }

    private func summary(_ title: String, seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.label(seconds))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func dayList(ledger: TimeLedger, days: [String]) -> some View {
        let peak = max(days.map { ledger.seconds(on: $0) }.max() ?? 0, 1)
        return List(days, id: \.self) { day in
            let seconds = ledger.seconds(on: day)
            HStack(spacing: 10) {
                Text(Self.dayLabel(day))
                    .frame(width: 84, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                GeometryReader { geometry in
                    Capsule()
                        .fill(seconds > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: max(4, geometry.size.width * seconds / peak), height: 8)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                Text(seconds > 0 ? Self.label(seconds) : "–")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(seconds > 0 ? .primary : .secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .listStyle(.inset)
    }

    static func label(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private static func dayLabel(_ day: String) -> String {
        guard let date = TimeLedger.date(from: day) else { return day }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
