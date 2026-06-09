#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

target="/Applications/Decks.app"

osascript -e 'quit app "Decks"' >/dev/null 2>&1 || true
for _ in $(seq 1 50); do
  pgrep -x Decks >/dev/null 2>&1 || break
  sleep 0.1
done

rm -rf "$target"
cp -R build/Decks.app "$target"
echo "Installed $target"

open "$target"
