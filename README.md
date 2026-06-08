# Decks

Notes that stay organized by context.

Each company, client or project is a *deck*. A deck holds four sections:

- **Daily** — a dated log for standups and things you want to bring up.
- **To-dos** — what to do or review, with a checkbox.
- **Notes** — a free markdown scratchpad: decisions, people, context.
- **Links** — quick access to repos, dashboards and docs.

The point is fast context switching. Open the app, pick the deck, and you are back where you left off, instead of digging through one giant notes file.

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

```
cd cli
cargo run -- list
cargo run -- add acme "review PR 214"
cargo run -- done acme 0
```

## Status

Early. The app covers the four sections and deck switching; the CLI covers listing and to-dos. Next: notes and daily from the CLI, and a quick-capture window.
