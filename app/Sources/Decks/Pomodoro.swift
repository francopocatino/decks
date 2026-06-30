import SwiftUI
import UserNotifications

extension Date {
    // A fixed anchor for TimelineView schedules. `from: .now` re-evaluates on
    // every render and reschedules in a tight loop, spinning the main thread.
    static let timelineAnchor = Date(timeIntervalSinceReferenceDate: 0)
}

// A focus timer (not tracked time — the Time engine already logs real work).
// Work → break → work, auto-cycling with a notification at each handoff.
//
// The live countdown is derived from `endsAt` by the views (via TimelineView),
// not stored and mutated every second: mutating observed state on a timer can
// land mid-layout and trap AppKit's constraint pass when hosted in a window.
@MainActor
@Observable
final class PomodoroEngine {
    enum Phase: String {
        case idle, work, shortBreak, longBreak

        var isBreak: Bool { self == .shortBreak || self == .longBreak }

        var title: String {
            switch self {
            case .idle: "Ready"
            case .work: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }
    }

    static let workKey = "pomodoroWorkMinutes"
    static let shortKey = "pomodoroShortMinutes"
    static let longKey = "pomodoroLongMinutes"

    private(set) var phase: Phase = .idle
    private(set) var running = false
    private(set) var phaseTotal: TimeInterval = 25 * 60
    private(set) var completed = 0
    private(set) var completedToday = 0

    @ObservationIgnored private var endsAt: Date?
    @ObservationIgnored private var pausedRemaining: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var dayStamp = TimeLedger.day(Date())

    private func minutes(_ key: String, _ fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : fallback
    }

    var workMinutes: Int { minutes(Self.workKey, 25) }
    var shortMinutes: Int { minutes(Self.shortKey, 5) }
    var longMinutes: Int { minutes(Self.longKey, 15) }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if running, let endsAt { return min(phaseTotal, max(0, endsAt.timeIntervalSince(now))) }
        return pausedRemaining
    }

    func fraction(at now: Date = Date()) -> Double {
        phaseTotal > 0 ? max(0, min(1, remaining(at: now) / phaseTotal)) : 0
    }

    func timeString(at now: Date = Date()) -> String {
        let total = Int(remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // Filled pomodoro dots in the current set of four.
    var setProgress: Int {
        completed == 0 ? 0 : (completed % 4 == 0 ? 4 : completed % 4)
    }

    func toggle() {
        switch phase {
        case .idle: begin(.work)
        default: running ? pause() : resume()
        }
    }

    func pause() {
        guard running else { return }
        pausedRemaining = remaining()
        running = false
        endsAt = nil
        stopTicker()
    }

    func resume() {
        guard !running, phase != .idle, pausedRemaining > 0 else { return }
        endsAt = Date().addingTimeInterval(pausedRemaining)
        running = true
        startTicker()
    }

    func reset() {
        stopTicker()
        phase = .idle
        running = false
        pausedRemaining = 0
        phaseTotal = TimeInterval(workMinutes * 60)
        completed = 0
        endsAt = nil
    }

    func skip() {
        guard phase != .idle else { return }
        complete(skipped: true)
    }

    private func minutes(for phase: Phase) -> Int {
        switch phase {
        case .work, .idle: workMinutes
        case .shortBreak: shortMinutes
        case .longBreak: longMinutes
        }
    }

    private func begin(_ phase: Phase) {
        rollover()
        self.phase = phase
        phaseTotal = TimeInterval(minutes(for: phase) * 60)
        pausedRemaining = phaseTotal
        endsAt = Date().addingTimeInterval(phaseTotal)
        running = true
        startTicker()
    }

    // Watches for the phase to elapse; it never touches observed state per
    // second, only on the actual transition.
    private func startTicker() {
        stopTicker()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.running, let endsAt = self.endsAt else { continue }
                if Date() >= endsAt { self.complete(skipped: false) }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func complete(skipped: Bool) {
        let finished = phase
        if finished == .work {
            completedToday += 1
            completed += 1
        }
        if !skipped { notify(finished) }
        switch finished {
        case .work:
            begin(completed % 4 == 0 ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            if finished == .longBreak { completed = 0 }
            begin(.work)
        case .idle:
            break
        }
    }

    private func rollover() {
        let today = TimeLedger.day(Date())
        if today != dayStamp {
            dayStamp = today
            completedToday = 0
            completed = 0
        }
    }

    private func notify(_ finished: Phase) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = finished == .work ? "Focus complete" : "Break over"
        content.body = finished == .work ? "Step back for a moment." : "Back to focus."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pomodoro-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

struct PomodoroView: View {
    @Environment(PomodoroEngine.self) private var pomodoro
    @Environment(DecksStore.self) private var store
    var compact = false

    private var ringSize: CGFloat { compact ? 156 : 208 }
    private var lineWidth: CGFloat { compact ? 11 : 14 }

    private var color: Color {
        if pomodoro.phase.isBreak { return .mint }
        if let deck = store.activeDeck, let tint = store.accentTint(for: deck) { return tint }
        return Color(red: 0.97, green: 0.37, blue: 0.34)
    }

    var body: some View {
        // Anchor the schedule to a fixed date; `from: .now` re-evaluates every
        // render and reschedules in a loop. Updates each half-second while
        // running, rarely otherwise — the engine never mutates state per second.
        TimelineView(.periodic(from: .timelineAnchor, by: pomodoro.running ? 0.5 : 3600)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: compact ? 16 : 24) {
            ring(now: now)
            dots
            controls
        }
        .padding(compact ? 20 : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(color)
    }

    private func ring(now: Date) -> some View {
        let fraction = pomodoro.phase == .idle ? 1 : pomodoro.fraction(at: now)
        let time = pomodoro.phase == .idle ? "\(pomodoro.workMinutes):00" : pomodoro.timeString(at: now)
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.3), radius: 6)
            VStack(spacing: 5) {
                Text(time)
                    .font(.system(size: ringSize * 0.21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(pomodoro.phase.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< 4, id: \.self) { index in
                Circle()
                    .fill(index < pomodoro.setProgress ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            Button { pomodoro.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(pomodoro.phase == .idle)

            Button { pomodoro.toggle() } label: {
                Image(systemName: pomodoro.running ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(color.gradient, in: Circle())
                    .shadow(color: color.opacity(0.4), radius: 8, y: 2)
            }
            .buttonStyle(.plain)

            Button { pomodoro.skip() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(pomodoro.phase == .idle)
        }
        .font(.body)
    }
}
