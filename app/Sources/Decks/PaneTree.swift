import AppKit
import SwiftUI

struct PaneTreeView: View {
    let slug: String
    let node: PaneNode
    var update: (PaneNode) -> Void
    var onClose: (() -> Void)?

    var body: some View {
        switch node {
        case let .leaf(section):
            LeafPane(
                slug: slug,
                section: section,
                onSection: { update(.leaf($0)) },
                onSplit: { axis in update(.split(axis, 0.5, .leaf(section), .leaf(section))) },
                onClose: onClose
            )
        case let .split(axis, fraction, first, second):
            SplitContainer(axis: axis, fraction: fraction) {
                update(.split(axis, $0, first, second))
            } first: {
                PaneTreeView(
                    slug: slug,
                    node: first,
                    update: { update(.split(axis, fraction, $0, second)) },
                    onClose: { update(second) }
                )
            } second: {
                PaneTreeView(
                    slug: slug,
                    node: second,
                    update: { update(.split(axis, fraction, first, $0)) },
                    onClose: { update(first) }
                )
            }
        }
    }
}

private struct LeafPane: View {
    let slug: String
    let section: DeckSection
    var onSection: (DeckSection) -> Void
    var onSplit: (SplitAxis) -> Void
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 160, minHeight: 120)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(DeckSection.allCases) { option in
                    Button { onSection(option) } label: {
                        Label(option.title, systemImage: option.symbol)
                    }
                }
            } label: {
                Label(section.title, systemImage: section.symbol)
                    .font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button { onSplit(.horizontal) } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.borderless)
            .help("Split right")

            Button { onSplit(.vertical) } label: {
                Image(systemName: "rectangle.split.1x2")
            }
            .buttonStyle(.borderless)
            .help("Split down")

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close pane")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .daily: DailyView(slug: slug)
        case .todos: TodosView(slug: slug)
        case .notes: NotesView(slug: slug)
        case .links: LinksView(slug: slug)
        case .meetings: MeetingsView(slug: slug)
        }
    }
}

private struct SplitContainer<First: View, Second: View>: View {
    let axis: SplitAxis
    let fraction: Double
    var onFraction: (Double) -> Void
    @ViewBuilder var first: First
    @ViewBuilder var second: Second

    @State private var dragFraction: Double?

    private let handle: CGFloat = 7
    private let minPane: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            let total = axis == .horizontal ? geometry.size.width : geometry.size.height
            let value = dragFraction ?? fraction
            let firstSize = max(minPane, min(total - minPane - handle, total * value))
            let secondSize = max(0, total - firstSize - handle)

            if axis == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: firstSize)
                    divider(total: total)
                    second.frame(width: secondSize)
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: firstSize)
                    divider(total: total)
                    second.frame(height: secondSize)
                }
            }
        }
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(Divider())
            .frame(
                width: axis == .horizontal ? handle : nil,
                height: axis == .vertical ? handle : nil
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = axis == .horizontal ? value.translation.width : value.translation.height
                        dragFraction = min(0.85, max(0.15, (total * fraction + delta) / total))
                    }
                    .onEnded { _ in
                        if let dragFraction { onFraction(dragFraction) }
                        dragFraction = nil
                    }
            )
    }
}
