#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh

target="/Applications/Decks.app"
rm -rf "$target"
cp -R build/Decks.app "$target"
echo "Installed $target"

open "$target"
