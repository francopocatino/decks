# On-disk format

Everything lives under `~/.decks`, or under `$DECKS_DIR` when that is set.

```
~/.decks/
  state.json            { "active": "<slug>" }
  <slug>/
    deck.json           deck metadata
    todos.json          array of to-dos
    links.json          array of links
    daily.md            free markdown, dated entries
    notes.md            free markdown
    reminders-sync.json app-internal Apple Reminders sync state
    time.json           seconds of context time per local day
```

Structured data is JSON, free text is markdown. Dates are RFC 3339 strings in UTC
(`2026-06-08T20:00:00Z`), without fractional seconds, so Swift and Rust both read
them without extra work.

## deck.json

```json
{ "slug": "acme", "name": "Acme", "createdAt": "2026-06-08T20:00:00Z" }
```

## todos.json

```json
[
  {
    "id": "5C9A2B1E-...-UUID",
    "text": "review PR 214",
    "done": false,
    "createdAt": "2026-06-08T20:00:00Z"
  }
]
```

`doneAt` is written only when the item is done. `due` is written only when the
item has a due date. Due dates sync with Apple Reminders using its floating
wall-clock semantics: after a timezone change the next sync re-anchors `due`
to the same local time, matching what the Reminders app shows.

`reminderID` is written only on decks that sync with Apple Reminders; it links
the to-do to its reminder. Preserve it when rewriting the file. The app keeps
its last-synced state in `reminders-sync.json` — leave that file alone.

## links.json

```json
[
  { "id": "UUID", "label": "Repo", "url": "https://github.com/...", "note": "" }
]
```
