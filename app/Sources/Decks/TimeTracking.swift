import AppKit
import CoreGraphics
import Foundation
import Observation

// Seconds of context time per local calendar day, persisted as time.json
// in the deck directory ({"2026-06-11": 4520}).
struct TimeLedger: Codable, Hashable {
    var days: [String: TimeInterval] = [:]

    mutating func add(_ seconds: TimeInterval, on day: String) {
        days[day, default: 0] += seconds
    }

    func seconds(on day: String) -> TimeInterval {
        days[day] ?? 0
    }

    func total(over days: [String]) -> TimeInterval {
        days.reduce(0) { $0 + seconds(on: $1) }
    }

    // DateFormatter is thread-safe for formatting on modern macOS and this
    // one is never mutated after creation; cached because day() sits on the
    // 1.5s tick path.
    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func date(from day: String) -> Date? {
        dayFormatter.date(from: day)
    }

    static func recentDays(_ count: Int, endingAt date: Date = Date()) -> [String] {
        let calendar = Calendar.current
        return (0 ..< count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map(day)
        }
    }
}

// Attributes awake, non-idle time to the active deck, whichever app is
// frontmost: a deck open in Decks means that context is the one being
// worked on. Accumulates in memory every loop tick and persists every
// 30 seconds and at quit.
@MainActor
@Observable
final class TimeTrackingEngine {
    static let idleLimit: TimeInterval = 120
    static let gapLimit: TimeInterval = 90

    private(set) var ledgers: [String: TimeLedger] = [:]
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var dirty: Set<String> = []

    init(store: DecksStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    func ledger(_ slug: String) -> TimeLedger {
        if let cached = ledgers[slug] { return cached }
        let loaded = Storage.readJSON(TimeLedger.self, at: Self.url(slug)) ?? TimeLedger()
        ledgers[slug] = loaded
        return loaded
    }

    // Without this, recreating a deck with the same slug resurrects the
    // deleted deck's history from the in-memory cache.
    func deckRemoved(_ slug: String) {
        ledgers[slug] = nil
        dirty.remove(slug)
    }

    func tick(now: Date = Date()) {
        let last = lastTick
        lastTick = now
        guard let last else { return }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed < Self.gapLimit else { return }
        guard Self.idleSeconds() < Self.idleLimit else { return }
        guard let slug = store.activeSlug, let deck = store.deck(slug), !deck.isArchived else { return }
        var ledger = ledger(slug)
        ledger.add(elapsed, on: TimeLedger.day(now))
        ledgers[slug] = ledger
        dirty.insert(slug)
        if now.timeIntervalSince(lastSave) > 30 {
            flush()
            lastSave = now
        }
    }

    private func flush() {
        for slug in dirty {
            guard let ledger = ledgers[slug] else { continue }
            Storage.writeJSON(ledger, to: Self.url(slug))
        }
        dirty = []
    }

    private static func url(_ slug: String) -> URL {
        Storage.deckDirectory(slug).appendingPathComponent("time.json")
    }

    private static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }
}
