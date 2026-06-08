import AppKit
import SwiftUI

@main
struct DecksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DecksStore()
    @State private var updates = UpdateChecker()
    @State private var identity = IdentityStore()
    @State private var chat = ChatStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(updates)
                .environment(identity)
                .environment(chat)
                .frame(minWidth: 760, minHeight: 460)
                .task { await updates.check() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.check() }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(identity)
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
