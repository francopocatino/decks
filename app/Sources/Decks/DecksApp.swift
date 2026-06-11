import AppKit
import SwiftUI

@main
struct DecksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store: DecksStore
    @State private var updates = UpdateChecker()
    @State private var identity: IdentityStore
    @State private var chat = ChatStore()
    @State private var reminders: RemindersSyncEngine
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    init() {
        let store = DecksStore()
        let identity = IdentityStore()
        _store = State(initialValue: store)
        _identity = State(initialValue: identity)
        _reminders = State(initialValue: RemindersSyncEngine(store: store, identity: identity))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(updates)
                .environment(identity)
                .environment(chat)
                .environment(reminders)
                .onAppear { NSApp.appearance = appearance.nsAppearance }
                .onChange(of: appearance) { _, value in NSApp.appearance = value.nsAppearance }
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
