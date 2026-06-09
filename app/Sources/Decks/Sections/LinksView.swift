import AppKit
import SwiftUI

struct LinksView: View {
    @Environment(DecksStore.self) private var store
    let slug: String
    @State private var label = ""
    @State private var url = ""
    @State private var editingID: UUID?
    @State private var editLabel = ""
    @State private var editURL = ""
    @FocusState private var editFocus: EditField?

    private enum EditField { case label, url }

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

    @ViewBuilder
    private func row(_ link: Link, shared: Bool = false) -> some View {
        if !shared, editingID == link.id {
            editRow(link)
        } else {
            linkButton(link, shared: shared)
        }
    }

    private func linkButton(_ link: Link, shared: Bool) -> some View {
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
                Button("Edit") { startEdit(link) }
                Button("Delete", role: .destructive) {
                    store.deleteLink(link.id, in: slug)
                }
            }
        }
    }

    private func editRow(_ link: Link) -> some View {
        HStack(spacing: 8) {
            TextField("Label", text: $editLabel)
                .frame(width: 140)
                .focused($editFocus, equals: .label)
            TextField("https://", text: $editURL)
                .focused($editFocus, equals: .url)
                .onSubmit { commitEdit(link) }
                .onExitCommand { editingID = nil }
            Button {
                commitEdit(link)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
        }
        .textFieldStyle(.plain)
    }

    private func startEdit(_ link: Link) {
        editLabel = link.label
        editURL = link.url
        editingID = link.id
        editFocus = .label
    }

    private func commitEdit(_ link: Link) {
        store.editLink(link.id, label: editLabel, url: editURL, in: slug)
        editingID = nil
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
