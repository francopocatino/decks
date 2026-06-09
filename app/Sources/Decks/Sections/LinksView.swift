import AppKit
import SwiftUI

struct LinksView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var label = ""
    @State private var url = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.links(slug).isEmpty, sharedLinks.isEmpty {
                ContentUnavailableView(
                    "No links",
                    systemImage: "link",
                    description: Text("Add repos, dashboards or docs you use for this deck.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.links(slug)) { link in
                        row(link)
                    }
                    if let parent, !sharedLinks.isEmpty {
                        Section("Shared from \(parent.name)") {
                            ForEach(sharedLinks) { link in
                                row(link, shared: true)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            composer
        }
    }

    private var parent: Deck? {
        store.deck(slug)?.parent.flatMap { store.deck($0) }
    }

    private var sharedLinks: [Link] {
        guard let parent else { return [] }
        return store.links(parent.slug)
    }

    private func row(_ link: Link, shared: Bool = false) -> some View {
        Button {
            open(link.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: shared ? "link.circle" : "link")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.label)
                    Text(link.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !shared {
                Button("Delete", role: .destructive) {
                    store.deleteLink(link.id, in: slug)
                }
            }
        }
    }

    private var composer: some View {
        HStack {
            TextField("Label", text: $label)
                .frame(width: 140)
            TextField("https://", text: $url)
                .onSubmit(add)
            Button(action: add) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .textFieldStyle(.plain)
        .padding(12)
        .background(.bar)
    }

    private func add() {
        store.addLink(label: label, url: url, to: slug)
        label = ""
        url = ""
    }

    private func open(_ string: String) {
        var value = string
        if !value.contains("://") { value = "https://" + value }
        guard let resolved = URL(string: value) else { return }
        NSWorkspace.shared.open(resolved)
    }
}
