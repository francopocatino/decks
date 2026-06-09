import AppKit
import SwiftUI

@main
struct DecksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DecksStore()
    @State private var updates = UpdateChecker()
    @State private var identity = IdentityStore()
    @State private var chat = ChatStore()
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(updates)
                .environment(identity)
                .environment(chat)
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

        Settings {
            SettingsView()
                .environment(identity)
                .environment(store)
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
