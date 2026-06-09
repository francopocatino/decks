<p align="center">
  <img src="assets/AppIcon-1024.png" width="120" alt="Decks">
</p>

<h1 align="center">Decks</h1>

<p align="center">
  Per-company notes for macOS, organized by context — built so work contexts never bleed into each other, with deep Claude integration.
</p>

<p align="center">
  <img src="https://github.com/francopocatino/decks/actions/workflows/ci.yml/badge.svg" alt="CI">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/macOS-15%2B-black.svg" alt="macOS 15+">
</p>

Each company, client or project is a *deck*. A deck holds four sections:

- **Daily** — a dated log for standups and things to bring up.
- **To-dos** — what to do or review, with a checkbox.
- **Notes** — a free markdown scratchpad: decisions, people, context.
- **Links** — quick access to repos, dashboards and docs.

Open the app, pick the deck, and you are back where you left off — instead of digging through one giant notes file. Daily and Notes render markdown with an edit/preview toggle.

## Install

```
git clone https://github.com/francopocatino/decks
cd decks
./scripts/install.sh        # builds Decks.app and installs it to /Applications
```

That builds a native `Decks.app`, installs it, and launches it. Right-click the Dock icon and choose Options > Keep in Dock. To run from source instead: `swift run --package-path app`.

## What it does

- Native macOS app (SwiftUI), no Electron.
- One deck per company/client/project, with rename / archive / delete, drag-to-reorder, and a sidebar that shows open to-do counts.
- Live sync: edits from the CLI or an agent show up in the open app within a second or two.
- Per-deck identity: git provider and commit email, project folders, which AI account the deck uses, and AI instructions (language, daily format, tone). API keys live in the macOS Keychain.
- Ask this deck: an in-app chat scoped to one deck, with persistent memory.
- A Rust CLI and an MCP server so Claude can read and write your decks.
- Worklog: turn a day's git commits into a daily entry.
- In-app update check; releases published on `v*` tags.

## Claude integration (MCP)

`decks-mcp` is an MCP server that exposes every deck operation as a tool, addressed by deck id. Register one global server:

```
cargo install --path cli                 # puts decks + decks-mcp on PATH
claude mcp add decks -- ~/.cargo/bin/decks-mcp
```

Then ask Claude — in Claude Code or Claude Desktop — to operate any deck by name:

- "add a to-do to acme: review the deploy"
- "fill the daily of nexus with what we did this session"
- "archive invicto"

`decks mcp-config` prints the ready-to-paste config. To keep a work account isolated, register a server **scoped** to one deck in that account's client only: `decks-mcp --deck <slug>` — it can never see another deck. The account boundary is which client/login you register the server in.

## Ask this deck (in-app AI)

Each deck has an Ask panel (the sparkles button) — a chat scoped to that deck. It answers only from that deck's own to-dos, daily, notes and links, keeps a persistent history, and uses that deck's AI account. A deck's chat never sees another deck's content or account. In-app chat needs an API-key account (set in the app settings, Cmd+,); login-account decks use Claude Code through the MCP server instead.

Each deck also carries free-form AI instructions (in deck settings) — language, daily format, tone. Ask prepends them to its system prompt, and Claude reads them from `show_deck` over the MCP server, so a daily drafted in one deck comes out in English bullets while another comes out in Spanish prose, per deck.

## CLI

The CLI reads and writes the same files as the app, and is the surface meant for automation.

```
cd cli
cargo run -- list                       # decks with open to-do counts
cargo run -- new "Acme"                 # create a deck
cargo run -- add acme "review PR 214"   # add a to-do
cargo run -- done acme 0                # toggle a to-do
cargo run -- note acme "use sqlite"     # append a note
cargo run -- daily acme "shipped auth"  # add a dated daily entry
cargo run -- show acme --json           # machine-readable output
```

Also: `link`/`unlink`, `remove` (to-do), `rename`/`archive`/`unarchive`/`delete` (deck), `worklog`, `which`. Every action is exposed as an MCP tool too.

## Worklog

`decks worklog <slug>` scans the deck's folders for git repositories, collects today's commits filtered to the deck's commit email, and prepends them to the daily log. A repo whose `origin` remote doesn't match the deck's git provider is skipped, so one job's commits never land in another's worklog. `decks which <path>` resolves a path to the deck whose folder contains it — together they make a Claude Code SessionEnd hook:

```
deck=$(decks which "$PWD") && [ -n "$deck" ] && decks worklog "$deck"
```

## How it stores data

Everything is plain files under `~/.decks` (override with `DECKS_DIR`): JSON for structured data, markdown for free text. The on-disk format is the only contract between the app and the CLI — see [docs/format.md](docs/format.md).

## Development

```
swift build  --package-path app                                  # app
cargo build  --manifest-path cli/Cargo.toml                      # cli + mcp
cargo test   --manifest-path cli/Cargo.toml
cargo fmt    --manifest-path cli/Cargo.toml --check
cargo clippy --manifest-path cli/Cargo.toml --all-targets -- -D warnings
```

CI runs all of the above on every pull request. Changes go through a branch and a pull request; commits are atomic; English only.

## License

MIT — see [LICENSE](LICENSE).
