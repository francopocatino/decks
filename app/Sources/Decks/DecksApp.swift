import AppKit
import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct DecksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: DecksStore
    @State private var updates = UpdateChecker()
    @State private var identity: IdentityStore
    @State private var chat: ChatStore
    @State private var reminders: RemindersSyncEngine
    @State private var notifications: NotificationScheduler
    @State private var tracker: TimeTrackingEngine
    @State private var spotlight: SpotlightIndexer
    @State private var mirror: CloudMirrorEngine
    @State private var popout: PopoutManager
    @State private var pomodoro: PomodoroEngine
    @State private var hotkey = HotkeyManager()
    @State private var capturePanel: QuickCapturePanel
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage(Pref.captureHotkey) private var captureHotkey: HotkeyOption = .ctrlOptSpace
    @AppStorage(Pref.pomodoroHotkey) private var pomodoroHotkey: HotkeyOption = .ctrlOptP

    init() {
        let store = DecksStore()
        let identity = IdentityStore()
        let chat = ChatStore()
        let reminders = RemindersSyncEngine(store: store, identity: identity)
        let tracker = TimeTrackingEngine(store: store)
        let spotlight = SpotlightIndexer(store: store)
        let mirror = CloudMirrorEngine(store: store)
        let pomodoro = PomodoroEngine()
        _store = State(initialValue: store)
        _identity = State(initialValue: identity)
        _chat = State(initialValue: chat)
        _reminders = State(initialValue: reminders)
        _notifications = State(initialValue: NotificationScheduler(store: store, identity: identity))
        _tracker = State(initialValue: tracker)
        _spotlight = State(initialValue: spotlight)
        _mirror = State(initialValue: mirror)
        _pomodoro = State(initialValue: pomodoro)
        _popout = State(initialValue: PopoutManager(store: store, identity: identity, tracker: tracker, pomodoro: pomodoro))
        _capturePanel = State(initialValue: QuickCapturePanel(store: store, pomodoro: pomodoro))
        // Single eviction point for every per-deck cache and engine, so an
        // external (CLI/Finder) delete cleans up the same as the in-app one.
        store.onDeckRemoved = { slug in
            reminders.deckRemoved(slug)
            tracker.deckRemoved(slug)
            spotlight.deckRemoved(slug)
            mirror.deckRemoved(slug)
            identity.forgetProfile(slug)
            chat.forget(slug)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(updates)
                .environment(identity)
                .environment(chat)
                .environment(reminders)
                .environment(notifications)
                .environment(tracker)
                .environment(spotlight)
                .environment(mirror)
                .environment(popout)
                .environment(pomodoro)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard
                        let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                        let slug = SpotlightEntry.slug(fromIdentifier: identifier),
                        store.deck(slug) != nil
                    else { return }
                    store.select(slug)
                }
                .onAppear {
                    NSApp.appearance = appearance.nsAppearance
                    hotkey.apply(captureHotkey, id: 1) { [capturePanel] in capturePanel.toggle() }
                    hotkey.apply(pomodoroHotkey, id: 2) { [pomodoro, popout] in
                        pomodoro.toggle()
                        popout.openPomodoro()
                    }
                }
                .onChange(of: appearance) { _, value in NSApp.appearance = value.nsAppearance }
                .onChange(of: captureHotkey) { _, value in
                    hotkey.apply(value, id: 1) { [capturePanel] in capturePanel.toggle() }
                }
                .onChange(of: pomodoroHotkey) { _, value in
                    hotkey.apply(value, id: 2) { [pomodoro, popout] in
                        pomodoro.toggle()
                        popout.openPomodoro()
                    }
                }
                .task { await updates.check() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.check() }
                }
            }
        }

        MenuBarExtra("Decks", systemImage: "rectangle.stack") {
            QuickCaptureView()
                .environment(store)
                .environment(pomodoro)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra {
            PomodoroView(compact: true)
                .environment(pomodoro)
                .environment(store)
                .frame(width: 264)
        } label: {
            if pomodoro.phase == .idle {
                Image(systemName: "timer")
            } else {
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
                    Text(pomodoro.timeString(at: context.date))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(identity)
                .environment(store)
                .environment(updates)
                .environment(hotkey)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if NotificationScheduler.isSupported {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["url"] as? String, let url = URL(string: raw) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
