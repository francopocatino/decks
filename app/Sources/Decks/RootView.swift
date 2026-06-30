import AppKit
import SwiftUI

struct RootView: View {
    @Environment(DecksStore.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @Environment(RemindersSyncEngine.self) private var reminders
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(TimeTrackingEngine.self) private var tracker
    @Environment(SpotlightIndexer.self) private var spotlight
    @Environment(CloudMirrorEngine.self) private var mirror
    @Environment(PopoutManager.self) private var popout
    @Environment(PomodoroEngine.self) private var pomodoro
    @Environment(\.openSettings) private var openSettings
    @State private var showingNewDeck = false
    @State private var newDeckName = ""
    @State private var newDeckParent: String?
    @State private var renaming: Deck?
    @State private var renameText = ""
    @State private var pendingDelete: Deck?
    @State private var showingPalette = false
    @State private var showingToday = false
    private let todayTag = "__today__"

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onChange(of: store.activeSlug) { _, _ in showingToday = false }
        .sheet(isPresented: $showingNewDeck) {
            DeckNameSheet(
                title: newDeckParent == nil ? "New deck" : "New sub-deck",
                name: $newDeckName,
                confirmLabel: "Create"
            ) {
                store.createDeck(name: newDeckName, parent: newDeckParent)
                newDeckName = ""
                newDeckParent = nil
                showingNewDeck = false
            } onCancel: {
                newDeckName = ""
                newDeckParent = nil
                showingNewDeck = false
            }
        }
        .sheet(item: $renaming) { deck in
            DeckNameSheet(title: "Rename deck", name: $renameText, confirmLabel: "Rename") {
                store.renameDeck(deck.slug, to: renameText)
                renaming = nil
            } onCancel: {
                renaming = nil
            }
        }
        .confirmationDialog("Delete this deck?", isPresented: deleteDialog, presenting: pendingDelete) { deck in
            Button("Delete \(deck.name)", role: .destructive) {
                store.deleteDeck(deck.slug)
            }
        } message: { _ in
            Text("This removes the deck and all its notes from disk. This cannot be undone.")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                store.reloadIfChanged()
                tracker.tick()
                spotlight.tick()
                mirror.tick()
                await reminders.tick()
                await notifications.tick()
            }
        }
        .background {
            Button("Command Palette") { showingPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .overlay { paletteOverlay }
        .animation(.easeOut(duration: 0.12), value: showingPalette)
        .toolbar {
            if let update = updates.update {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await updates.install() }
                    } label: {
                        if updates.installing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Update \(update.version)", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .disabled(updates.installing)
                    .help("Install version \(update.version) and relaunch")
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if showingToday {
            TodayView(onOpenDeck: { slug in
                showingToday = false
                store.select(slug)
            })
        } else if let deck = store.activeDeck {
            DeckDetailView(deck: deck)
                .id(deck.slug)
        } else {
            ContentUnavailableView(
                "No deck yet",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Create one for each project or context you switch between.")
            )
        }
    }

    private var sidebar: some View {
        List(selection: selectionBinding) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .tag(todayTag)
            }
            Section("Decks") {
                ForEach(store.topLevelVisibleDecks()) { deck in
                    let children = store.visibleChildren(of: deck.slug)
                    if children.isEmpty {
                        deckRow(deck)
                    } else {
                        DisclosureGroup {
                            ForEach(children) { child in
                                deckRow(child)
                            }
                            .onMove { store.moveDecks(parent: deck.slug, fromOffsets: $0, toOffset: $1) }
                        } label: {
                            deckRow(deck)
                        }
                    }
                }
                .onMove { store.moveDecks(parent: nil, fromOffsets: $0, toOffset: $1) }
            }
            if !store.archivedDecks.isEmpty {
                Section("Archived") {
                    ForEach(store.archivedDecks) { deck in
                        deckRow(deck)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    startNewDeck(parent: nil)
                } label: {
                    Label("New deck", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n")
                Spacer()
                Button {
                    store.settingsSection = .general
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(12)
        }
    }

    private func deckRow(_ deck: Deck) -> some View {
        Label {
            Text(deck.name)
        } icon: {
            DeckIcon(deck: deck, accent: store.accent(for: deck))
        }
        .badge(badge(for: deck))
            .tag(deck.slug)
            .contextMenu {
                Button("Rename") { startRename(deck) }
                Button("Settings…") {
                    store.settingsDeck = deck.slug
                    store.settingsSection = .decks
                    openSettings()
                }
                if deck.parent == nil, !deck.isArchived {
                    Button("Add sub-deck") { startNewDeck(parent: deck.slug) }
                }
                if deck.isArchived {
                    Button("Unarchive") { store.setArchived(deck.slug, false) }
                } else {
                    Button("Archive") { store.setArchived(deck.slug, true) }
                }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = deck }
            }
    }

    private func startNewDeck(parent: String?) {
        newDeckName = ""
        newDeckParent = parent
        showingNewDeck = true
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        if showingPalette {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.black.opacity(0.06))
                    .ignoresSafeArea()
                    .onTapGesture { showingPalette = false }
                CommandPalette(isPresented: $showingPalette, actions: paletteActions)
                    .padding(.top, 88)
            }
            .transition(.opacity)
        }
    }

    private var paletteActions: [CommandAction] {
        [
            CommandAction(id: "today", title: "Today", subtitle: "Overview across decks", symbol: "sun.max") {
                showingToday = true
            },
            CommandAction(id: "pomodoro", title: "Pomodoro", subtitle: "Open the focus timer", symbol: "timer") {
                popout.openPomodoro()
            },
            CommandAction(id: "pomodoro-toggle", title: pomodoro.running ? "Pause focus" : "Start focus", subtitle: nil, symbol: pomodoro.running ? "pause" : "play") {
                pomodoro.toggle()
            },
            CommandAction(id: "new-deck", title: "New deck", subtitle: nil, symbol: "plus") {
                startNewDeck(parent: nil)
            },
            CommandAction(id: "settings", title: "Open Settings", subtitle: nil, symbol: "gearshape") {
                store.settingsSection = .general
                openSettings()
            },
        ]
    }

    private func badge(for deck: Deck) -> Text? {
        let count = store.openTodoCount(deck.slug)
        return count > 0 ? Text("\(count)") : nil
    }

    private func startRename(_ deck: Deck) {
        renameText = deck.name
        renaming = deck
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { showingToday ? todayTag : store.activeSlug },
            set: { value in
                if value == todayTag {
                    showingToday = true
                } else if let slug = value {
                    showingToday = false
                    store.select(slug)
                }
            }
        )
    }

    private var deleteDialog: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

private struct DeckNameSheet: View {
    let title: String
    @Binding var name: String
    let confirmLabel: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("Project or context", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(onConfirm)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button(confirmLabel, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
