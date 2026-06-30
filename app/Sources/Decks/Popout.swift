import AppKit
import SwiftUI

// Renders one deck section standalone, reused by the tiling panes and the
// pop-out window so a detached section looks identical to an inline one.
struct DeckSectionView: View {
    let slug: String
    let section: DeckSection

    var body: some View {
        switch section {
        case .daily: DailyView(slug: slug)
        case .todos: TodosView(slug: slug)
        case .notes: NotesView(slug: slug)
        case .links: LinksView(slug: slug)
        case .meetings: MeetingsView(slug: slug)
        case .time: TimeView(slug: slug)
        }
    }
}

// Floating, borderless, resizable companion windows: pop a section out next to
// a call and keep it on top. Non-activating so clicking it doesn't pull focus
// from the app underneath, yet still key-able for editing.
@MainActor
@Observable
final class PopoutManager {
    @ObservationIgnored private let store: DecksStore
    @ObservationIgnored private let identity: IdentityStore
    @ObservationIgnored private let tracker: TimeTrackingEngine
    @ObservationIgnored private var panels: [String: PopoutPanel] = [:]

    init(store: DecksStore, identity: IdentityStore, tracker: TimeTrackingEngine) {
        self.store = store
        self.identity = identity
        self.tracker = tracker
    }

    func open(slug: String, section: DeckSection) {
        let key = "\(slug)/\(section.rawValue)"
        if let existing = panels[key] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = PopoutPanel(key: key)
        panel.onClose = { [weak self] in self?.panels[key] = nil }

        let accent = store.deck(slug).flatMap { store.accentTint(for: $0) }
        let content = PopoutView(
            slug: slug,
            section: section,
            deckName: store.deck(slug)?.name ?? slug,
            accent: accent,
            setPinned: { [weak panel] pinned in panel?.level = pinned ? .floating : .normal },
            onClose: { [weak panel] in panel?.close() }
        )
        .environment(store)
        .environment(identity)
        .environment(tracker)
        .background(.regularMaterial)

        let hosting = NSHostingController(rootView: content)
        panel.contentViewController = hosting
        // Titled (not borderless) so the window's frame view supplies native
        // edge resizing and its cursors at any level — a borderless panel loses
        // the resize cursor once it floats. The title bar is hidden, so it still
        // reads as a chromeless minimal window.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 280, height: 220)
        panel.setContentSize(NSSize(width: 440, height: 560))
        positionCascading(panel)

        panels[key] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    // Step each new window down-right from the last so stacked pop-outs don't
    // land exactly on top of one another.
    private func positionCascading(_ panel: PopoutPanel) {
        guard let screen = NSScreen.main else { return }
        let step = CGFloat(panels.count) * 26
        let frame = panel.frame
        let origin = NSPoint(
            x: min(screen.visibleFrame.maxX - frame.width - 24, screen.visibleFrame.minX + 80 + step),
            y: max(screen.visibleFrame.minY + 24, screen.visibleFrame.maxY - frame.height - 80 - step)
        )
        panel.setFrameOrigin(origin)
    }
}

final class PopoutPanel: NSPanel {
    let key: String
    var onClose: (() -> Void)?

    init(key: String) {
        self.key = key
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        onClose?()
        super.close()
    }
}

private struct PopoutView: View {
    let slug: String
    let section: DeckSection
    let deckName: String
    let accent: Color?
    var setPinned: (Bool) -> Void
    var onClose: () -> Void

    @State private var pinned = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            DeckSectionView(slug: slug, section: section)
        }
        .tint(accent ?? .accentColor)
    }

    // A thin title strip, sized like a window title bar so it reads as window
    // chrome rather than a second toolbar above the section's own header.
    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .help("Close")

            Spacer()

            Text("\(section.title) · \(deckName)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                pinned.toggle()
                setPinned(pinned)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .help(pinned ? "Floating on top — click to unpin" : "Pin to float on top")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
