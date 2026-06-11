# Automation recipes

The `decks` CLI is the bridge between Decks and Apple's automation stack. No
App Intents, no companion apps — Shortcuts and SSH drive the same plain files
the app reads. Install the CLI first (`cargo install --path cli`), it lands in
`~/.cargo/bin/decks`.

## Switch deck when a Focus turns on

Focus modes sync across devices, so turning on a work Focus from the iPhone or
Watch switches the deck on the Mac.

1. On the Mac, open **Shortcuts → Automations → New Automation** (macOS 26+).
2. Pick the Focus under **Focus Modes**, choose **When turning on** and
   **Run immediately**.
3. Add a **Run Shell Script** action:

   ```sh
   ~/.cargo/bin/decks open acme
   ```

The running app notices `state.json` changed and selects the deck within a
couple of seconds.

## Capture from iPhone or Apple Watch over SSH

Shortcuts on iOS/watchOS has **Run Script Over SSH** — point it at the Mac and
quick capture works from anywhere (pair it with Tailscale to make the Mac
reachable away from home).

1. On the Mac: **System Settings → General → Sharing → Remote Login** (on).
2. On the iPhone, create a shortcut: **Ask for Input** (Text) →
   **Run Script Over SSH**:

   ```sh
   ~/.cargo/bin/decks add acme "$(printf '%s' "Provided Input")"
   ```

   Host: the Mac's Tailscale/LAN name, user: your macOS user, authentication:
   SSH key.
3. Add it to the Watch / Home Screen / Action button. `decks daily` works the
   same way for daily-log lines.

## Anything else

Every command works from Shortcuts' **Run Shell Script** on the Mac:
`decks list --json` feeds **Get Dictionary from Input** for menus, `decks
worklog <slug>` appends today's git activity on a schedule, and so on. Run
`decks --help` for the full surface.
