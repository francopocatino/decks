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

`doneAt` is written only when the item is done.

## links.json

```json
[
  { "id": "UUID", "label": "Repo", "url": "https://github.com/...", "note": "" }
]
```
