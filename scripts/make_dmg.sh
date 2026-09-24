#!/usr/bin/env bash
#
# Build a distributable .dmg (drag-to-Applications) from the notarized app,
# then notarize + staple the dmg itself.
# Run scripts/package.sh first (it produces the signed/stapled .app).
#
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build-release/Build/Products/Release/Playporter.app"
if [ ! -d "$APP" ]; then
    echo "❌ App introuvable — lance d'abord ./scripts/package.sh"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="Playporter-$VERSION.dmg"
rm -f "$DMG"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "▶︎ Installation de create-dmg…"
    brew install create-dmg >/dev/null
fi

echo "▶︎ Création du DMG…"
create-dmg \
    --volname "Playporter" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 120 \
    --icon "Playporter.app" 150 190 \
    --app-drop-link 390 190 \
    --hide-extension "Playporter.app" \
    --no-internet-enable \
    "$DMG" "$APP" || true

if [ ! -f "$DMG" ]; then
    echo "❌ Le DMG n'a pas été créé."
    exit 1
fi

echo "▶︎ Notarisation du DMG…"
xcrun notarytool submit "$DMG" --keychain-profile itinnove --wait

echo "▶︎ Agrafage…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "✅ $DMG (notarisé + agrafé)"
