import AppKit
import SwiftUI

enum DeckColor: String, CaseIterable, Identifiable {
    case gray, red, orange, yellow, green, teal, blue, purple, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .gray: .secondary
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }

    var nsColor: NSColor {
        switch self {
        case .gray: .systemGray
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        }
    }
}

extension Deck {
    var accent: Color {
        color.flatMap { DeckColor(rawValue: $0) }?.color ?? .secondary
    }
}

@MainActor
extension DecksStore {
    // Family accent as concrete colors; nil when the deck has no color of
    // its own or inherited, so callers can fall back to system defaults.
    func accentTint(for deck: Deck) -> Color? {
        accent(for: deck).flatMap { DeckColor(rawValue: $0)?.color }
    }

    func accentNSColor(for deck: Deck) -> NSColor {
        accent(for: deck).flatMap { DeckColor(rawValue: $0)?.nsColor } ?? .controlAccentColor
    }
}

// Every deck gets a mark: a filled dot for top-level decks, a ring for
// sub-decks (in the parent's color when they have none of their own).
// Drawn as a non-template NSImage because AppKit menus drop SwiftUI shapes
// and recolor template symbols — this renders identically in the sidebar,
// settings and menus.
struct DeckIcon: View {
    let deck: Deck
    var accent: String?
    var indented: Bool

    // `indented` widens sub-deck swatches so menus (which can't indent
    // items) still show one level of depth; lists indent on their own.
    init(deck: Deck, accent: String? = nil, indented: Bool = false) {
        self.deck = deck
        self.accent = accent ?? deck.color
        self.indented = indented && deck.parent != nil
    }

    var body: some View {
        if deck.isArchived {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
        } else {
            Image(nsImage: Self.swatch(color: nsAccent, filled: deck.parent == nil, indented: indented))
        }
    }

    private var nsAccent: NSColor {
        accent.flatMap { DeckColor(rawValue: $0) }?.nsColor ?? .secondaryLabelColor
    }

    private static func swatch(color: NSColor, filled: Bool, indented: Bool) -> NSImage {
        let dot: CGFloat = 12
        let offset: CGFloat = indented ? 14 : 0
        let image = NSImage(size: NSSize(width: dot + offset, height: dot), flipped: false) { rect in
            let circle = NSRect(x: rect.minX + offset, y: rect.minY, width: dot, height: dot)
            let path = NSBezierPath(ovalIn: circle.insetBy(dx: 1.5, dy: 1.5))
            if filled {
                color.setFill()
                path.fill()
            } else {
                color.setStroke()
                path.lineWidth = 1.8
                path.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
