#!/usr/bin/env bash
#
# Generate latest.json (auto-update manifest) from the built, notarized .zip.
# Run after scripts/package.sh. The .zip must be served at
# https://playporter.itinnove.com/<zip name> (i.e. deployed with the site).
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build-release/Build/Products/Release/Playporter.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="Playporter-$VERSION.zip"

if [ ! -f "$ZIP" ]; then
    echo "❌ $ZIP introuvable — lance d'abord ./scripts/package.sh"
    exit 1
fi

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
NOTES="${1:-Mise à jour Playporter $VERSION}"

cat > latest.json <<EOF
{
  "version": "$VERSION",
  "url": "https://playporter.itinnove.com/$ZIP",
  "sha256": "$SHA",
  "notes": "$NOTES"
}
EOF

echo "✅ latest.json généré :"
cat latest.json | sed 's/^/  /'
