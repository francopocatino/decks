# Decks

Notes that stay organized by context.

Each company, client or project is a *deck*. A deck holds four sections:

- **Daily** — a dated log for standups and things you want to bring up.
- **To-dos** — what to do or review, with a checkbox.
- **Notes** — a free markdown scratchpad: decisions, people, context.
- **Links** — quick access to repos, dashboards and docs.

The point is fast context switching. Open the app, pick the deck, and you are back where you left off, instead of digging through one giant notes file.

Daily and Notes render markdown — headings, lists, bold, code — with an edit/preview toggle.

## Layout

- `app/` — the macOS app (SwiftUI, built as a SwiftPM executable).
- `cli/` — a small Rust CLI over the same files, meant as the surface for automation later.
- `docs/format.md` — the on-disk format both sides agree on.

Both read and write plain files under `~/.decks` (override with `DECKS_DIR`). The contract is the file format, not a shared library, so each side stays idiomatic.

## Run the app

```
cd app
swift run
```

Or open the `app` folder in Xcode and press Run.

## Build and install the app

Build a real `Decks.app` and install it to `/Applications`:

```
./scripts/install.sh
```

That builds the bundle, copies it to `/Applications/Decks.app` and launches it. From there it behaves like any native app: double-click to open, and right-click the Dock icon and choose Options > Keep in Dock to keep it there.

To build the bundle without installing, run `./scripts/bundle.sh` (output in `build/Decks.app`). To regenerate the icon, run `./scripts/make_icon.sh`.

## Updates

On launch the app checks GitHub for the latest release and shows a banner when a newer version is available; "Check for Updates…" in the app menu does the same on demand. Releases are published automatically when a `v*` tag is pushed.

## Use the CLI

The CLI reads and writes the same files as the app, and is the surface meant for automation.

```
cd cli
cargo run -- new "Acme"                 # create a deck
cargo run -- add acme "review PR 214"   # add a to-do
cargo run -- done acme 0                # toggle a to-do
cargo run -- note acme "use sqlite"     # append a note
cargo run -- daily acme "shipped auth"  # add a dated daily entry
cargo run -- list --json                # machine-readable output
cargo run -- show acme --json
```

Also: `link`/`unlink`, `remove` (to-do), `rename`/`archive`/`unarchive`/`delete` (deck), `worklog`, `which`. Everything the app does is on the CLI, and exposed as MCP tools.

## Claude integration (MCP)

`decks-mcp` is an MCP server that exposes deck operations as tools, so Claude (Claude Code or Claude Desktop) can read and write your decks.

To keep work contexts isolated, scope a server to a single deck with `--deck <slug>` (or the `DECKS_DECK` env var). A scoped server only ever sees that deck: it cannot list, read or write any other, so separate jobs never leak into one another.

Generate the snippet for a deck with `decks mcp-config <slug>`.

```json
{
  "mcpServers": {
    "decks-nexus": {
      "command": "/path/to/decks-mcp",
      "args": ["--deck", "nexus"]
    }
  }
}
```

## Per-deck identity

Each deck can carry its own identity: a git provider (GitHub or GitLab) and commit email, the repositories it owns, and which AI account it uses. Open it from the deck's context menu (Settings…).

AI accounts are managed in the app settings (Cmd+,) as named entities; several decks can share one account, or a deck can keep its own. API keys live in the macOS Keychain, never in `~/.decks`.

## Ask this deck (AI)

Each deck has an "Ask" panel (the sparkles button) — a chat scoped to that deck. It answers only from that deck's own to-dos, daily log, notes and links, keeps a persistent history in `~/.decks/<slug>/chat.json`, and uses that deck's AI account. A deck's chat never sees another deck's content or account.

In-app chat needs an account in API-key mode (set in Settings…). Decks on a Claude login account use Claude Code through the scoped MCP server instead.

## Worklog

`decks worklog <slug>` reads the deck's repositories (set in Settings…), collects today's commits filtered to the deck's commit email, and prepends them to the deck's daily log. A repo whose `origin` remote doesn't match the deck's git provider is skipped with a warning, so one job's commits never land in another's worklog.

`decks which <path>` prints the deck that owns a repository path. Together they make a Claude Code SessionEnd hook that captures coding sessions automatically:

```
deck=$(decks which "$PWD") && [ -n "$deck" ] && decks worklog "$deck"
```

## Status

Early. The app covers the four sections and deck switching; the CLI covers listing and to-dos. Next: notes and daily from the CLI, and a quick-capture window.
