#!/usr/bin/env bash
#
# Build → sign (Developer ID + hardened runtime) → notarize → staple → zip.
# Requires:
#   - "Developer ID Application: IT INNOVE (595VPP3XGG)" in the keychain
#   - a notarytool keychain profile named "itinnove"
#     (xcrun notarytool store-credentials "itinnove" --apple-id <email> --team-id 595VPP3XGG)
#
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: IT INNOVE (595VPP3XGG)"
PROFILE="itinnove"
SCHEME="Playporter"
BUILD_DIR="./build-release"
APP="$BUILD_DIR/Build/Products/Release/Playporter.app"

echo "▶︎ Génération du projet Xcode…"
xcodegen generate >/dev/null

echo "▶︎ Build Release…"
xcodebuild -project Playporter.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build >/dev/null

echo "▶︎ Signature Developer ID + hardened runtime…"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "▶︎ Vérification de la signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
NOTARIZE_ZIP="$BUILD_DIR/Playporter-notarize.zip"

echo "▶︎ Zip pour notarisation…"
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"

echo "▶︎ Soumission à la notarisation (profil: $PROFILE)…"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$PROFILE" --wait

echo "▶︎ Agrafage du ticket…"
xcrun stapler staple "$APP"

DIST="Playporter-$VERSION.zip"
rm -f "$DIST"
echo "▶︎ Zip distribuable final…"
ditto -c -k --keepParent "$APP" "$DIST"

echo ""
echo "✅ Terminé : $DIST (signé, notarisé, agrafé)"
echo "   Vérification Gatekeeper :"
spctl -a -vv --type execute "$APP" || true
