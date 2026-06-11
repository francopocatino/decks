import AppKit
import SwiftUI

// A Spotlight-style floating capture panel, summoned by the global hotkey.
// Non-activating, so it types without stealing the frontmost app's focus.
@MainActor
final class QuickCapturePanel {
    private let store: DecksStore
    private var panel: CapturePanel?

    init(store: DecksStore) {
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let content = QuickCaptureView(focusOnAppear: true) { [weak self] in self?.close() }
            .environment(store)
        let panel = CapturePanel(contentViewController: NSHostingController(rootView: content))
        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }
        if let screen = NSScreen.main {
            let frame = panel.frame
            let origin = NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.minY + screen.visibleFrame.height * 0.62
            )
            panel.setFrameOrigin(origin)
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.close()
        panel = nil
    }
}

private final class CapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onCancel?()
    }
}
