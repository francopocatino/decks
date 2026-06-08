#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/Decks.app"
version="${DECKS_VERSION:-0.1.0}"

swift build -c release --package-path app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp app/.build/release/Decks "$app/Contents/MacOS/Decks"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/${version}/g" scripts/Info.plist > "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
