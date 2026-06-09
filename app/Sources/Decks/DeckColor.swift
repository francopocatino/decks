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
}

extension Deck {
    var accent: Color {
        color.flatMap { DeckColor(rawValue: $0) }?.color ?? .secondary
    }
}
