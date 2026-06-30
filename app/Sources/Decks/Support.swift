import Foundation

// UserDefaults keys shared between Settings views and the engines that
// read them — a typo here breaks one place loudly instead of two silently.
enum Pref {
    static let meetingAlerts = "meetingAlerts"
    static let meetingAlertLead = "meetingAlertLead"
    static let dueAlerts = "dueAlerts"
    static let icloudMirror = "icloudMirror"
    static let captureHotkey = "captureHotkey"
    static let pomodoroHotkey = "pomodoroHotkey"
    static let markdownToolbar = "markdownToolbar"
    static let spotlightIndexed = "spotlightIndexedDecks"
    static let cloudMirrorFiles = "cloudMirrorFiles"
}

// Time gate for the engines ticking on RootView's loop.
struct Throttle {
    let interval: TimeInterval
    private var last = Date.distantPast

    init(_ interval: TimeInterval) {
        self.interval = interval
    }

    mutating func ready(now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(last) > interval else { return false }
        last = now
        return true
    }
}

extension Date {
    // Reminders carries due dates at minute precision; everything that
    // stores or compares a due date goes through this.
    func truncatedToMinute(calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)) ?? self
    }
}
