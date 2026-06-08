import AppKit
import SwiftUI

@main
struct DecksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = DecksStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 460)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 980, height: 640)
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
