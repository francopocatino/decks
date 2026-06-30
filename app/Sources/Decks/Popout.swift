import AppKit
import SwiftUI

// Renders one deck section standalone, reused by the tiling panes and the
// pop-out window so a detached section looks identical to an inline one.
struct DeckSectionView: View {
    let slug: String
    let section: DeckSection
    // The pop-out hides the editor sections' own header for a focused, single-bar
    // surface; the tiling panes keep it.
    var chrome = true

    var body: some View {
        switch section {
        case .daily: DailyView(slug: slug, chrome: chrome)
        case .todos: TodosView(slug: slug)
        case .notes: NotesView(slug: slug, chrome: chrome)
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
    @ObservationIgnored private let pomodoro: PomodoroEngine
    @ObservationIgnored private var panels: [String: PopoutPanel] = [:]

    init(store: DecksStore, identity: IdentityStore, tracker: TimeTrackingEngine, pomodoro: PomodoroEngine) {
        self.store = store
        self.identity = identity
        self.tracker = tracker
        self.pomodoro = pomodoro
    }

    func open(slug: String, section: DeckSection) {
        let key = "\(slug)/\(section.rawValue)"
        let accent = store.deck(slug).flatMap { store.accentTint(for: $0) }
        present(
            key: key,
            title: "\(section.title) · \(store.deck(slug)?.name ?? slug)",
            accent: accent,
            size: NSSize(width: 440, height: 560),
            content: DeckSectionView(slug: slug, section: section, chrome: false)
        )
    }

    func openPomodoro() {
        let accent = store.activeDeck.flatMap { store.accentTint(for: $0) }
            ?? Color(red: 0.97, green: 0.37, blue: 0.34)
        present(
            key: "__pomodoro__",
            title: "Pomodoro",
            accent: accent,
            size: NSSize(width: 320, height: 384),
            content: PomodoroView()
        )
    }

    private func present(key: String, title: String, accent: Color?, size: NSSize, content: some View) {
        if let existing = panels[key] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = PopoutPanel(key: key)
        panel.onClose = { [weak self] in self?.panels[key] = nil }

        let view = PopoutView(
            title: title,
            accent: accent,
            setPinned: { [weak panel] pinned in panel?.level = pinned ? .floating : .normal },
            onClose: { [weak panel] in panel?.close() },
            content: content
        )
        .environment(store)
        .environment(identity)
        .environment(tracker)
        .environment(pomodoro)
        .background(.regularMaterial)

        let hosting = NSHostingController(rootView: view)
        // Fill the whole window, including the transparent title-bar band, so
        // the title strip sits at the very top instead of below an empty gap.
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        // Host the SwiftUI view as a SUBVIEW, not the window's content view:
        // when the hosting view IS the content view, AppKit derives the window's
        // content-size extrema by re-evaluating the view, and dynamic content
        // (the pomodoro ring) mutates the graph mid constraint pass and traps.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        // Size the hosting view by frame, not Auto Layout: as constraint-based
        // content it re-enters the constraint update cycle on every re-render
        // (the pomodoro ring ticks), looping the layout pass.
        hosting.view.translatesAutoresizingMaskIntoConstraints = true
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
        panel.hosting = hosting
        panel.contentView = container
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
        panel.minSize = NSSize(width: 260, height: 200)
        panel.setContentSize(size)
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
    var hosting: NSViewController?

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

private struct PopoutView<Content: View>: View {
    let title: String
    let accent: Color?
    var setPinned: (Bool) -> Void
    var onClose: () -> Void
    let content: Content

    @State private var pinned = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
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
            .foregroundStyle(.secondary)
            .help("Close")

            Spacer()

            Text(title)
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
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }
}
