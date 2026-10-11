#!/bin/bash
# Build Release and package it for distribution: zip, DMG, checksums in dist/.
# The build is stripped of debug maps so no local paths ship, then scripts/privacy-check.sh gates the output.
set -euo pipefail
cd "$(dirname "$0")/.."

# Build outside the repo so object-file paths never contain the checkout location.
DERIVED=$(mktemp -d)
STAGE=$(mktemp -d)
trap 'rm -rf "$DERIVED" "$STAGE"' EXIT

xcodegen generate
xcodebuild -project Desklamp.xcodeproj -scheme Desklamp -configuration Release -derivedDataPath "$DERIVED" -quiet \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=all COPY_PHASE_STRIP=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  OTHER_SWIFT_FLAGS="-file-prefix-map $PWD=. -file-prefix-map $DERIVED=/build" \
  OTHER_CFLAGS="-ffile-prefix-map=$PWD=. -ffile-prefix-map=$DERIVED=/build" \
  build

# Work on a copy so the build products stay untouched.
rm -rf dist
mkdir dist
APP="$STAGE/Desklamp.app"
ditto --norsrc --noextattr "$DERIVED/Build/Products/Release/Desklamp.app" "$APP"
BIN="$APP/Contents/MacOS/Desklamp"

# Belt and braces: drop any remaining local symbols from every architecture, then re-sign (ad hoc, entitlements kept).
if nm -pa "$BIN" 2>/dev/null | grep -q '/Users/'; then
  strip -S -x "$BIN"
  codesign --force --sign - --timestamp=none --entitlements Desklamp/Desklamp.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - "$APP" 2>&1 | grep -q 'com.apple.security.app-sandbox' \
  || { echo "package: app-sandbox entitlement missing after signing" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

# Desklamp.zip is the stable name the npm installer downloads.
ditto -c -k --keepParent --norsrc --noextattr "$APP" "dist/Desklamp-$VERSION.zip"
cp "dist/Desklamp-$VERSION.zip" dist/Desklamp.zip

# DMG: the app plus an Applications symlink to drag onto.
DMGSRC="$STAGE/dmg"
mkdir "$DMGSRC"
ditto --norsrc --noextattr "$APP" "$DMGSRC/Desklamp.app"
ln -s /Applications "$DMGSRC/Applications"
hdiutil create -quiet -volname Desklamp -srcfolder "$DMGSRC" -format UDZO -ov "dist/Desklamp-$VERSION.dmg"

(cd dist && shasum -a 256 Desklamp.zip "Desklamp-$VERSION.zip" "Desklamp-$VERSION.dmg" > SHA256SUMS)

scripts/privacy-check.sh
echo "Packaged Desklamp $VERSION in dist/"
