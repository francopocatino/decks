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
    @State private var chat = ChatStore()
    @State private var reminders: RemindersSyncEngine
    @State private var notifications: NotificationScheduler
    @State private var tracker: TimeTrackingEngine
    @State private var spotlight: SpotlightIndexer
    @State private var mirror: CloudMirrorEngine
    @State private var hotkey = HotkeyManager()
    @State private var capturePanel: QuickCapturePanel
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("captureHotkey") private var captureHotkey: HotkeyOption = .ctrlOptSpace

    init() {
        let store = DecksStore()
        let identity = IdentityStore()
        _store = State(initialValue: store)
        _identity = State(initialValue: identity)
        _reminders = State(initialValue: RemindersSyncEngine(store: store, identity: identity))
        _notifications = State(initialValue: NotificationScheduler(store: store, identity: identity))
        _tracker = State(initialValue: TimeTrackingEngine(store: store))
        _spotlight = State(initialValue: SpotlightIndexer(store: store))
        _mirror = State(initialValue: CloudMirrorEngine(store: store))
        _capturePanel = State(initialValue: QuickCapturePanel(store: store))
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
                    hotkey.apply(captureHotkey) { [capturePanel] in capturePanel.toggle() }
                }
                .onChange(of: appearance) { _, value in NSApp.appearance = value.nsAppearance }
                .onChange(of: captureHotkey) { _, value in
                    hotkey.apply(value) { [capturePanel] in capturePanel.toggle() }
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
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(identity)
                .environment(store)
                .environment(updates)
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
