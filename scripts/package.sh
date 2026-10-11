#!/bin/bash
# Build Release and package it for distribution: zip, DMG, checksums in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project Desklamp.xcodeproj -scheme Desklamp -configuration Release -derivedDataPath build -quiet build

APP=build/Build/Products/Release/Desklamp.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

rm -rf dist
mkdir dist

# Zip keeps the signature and xattrs. Desklamp.zip is the stable name the npm installer downloads.
ditto -c -k --keepParent "$APP" "dist/Desklamp-$VERSION.zip"
cp "dist/Desklamp-$VERSION.zip" dist/Desklamp.zip

# DMG: the app plus an Applications symlink to drag onto.
ditto "$APP" "$STAGE/Desklamp.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Desklamp -srcfolder "$STAGE" -format UDZO -ov "dist/Desklamp-$VERSION.dmg"

(cd dist && shasum -a 256 Desklamp.zip "Desklamp-$VERSION.zip" "Desklamp-$VERSION.dmg" > SHA256SUMS)
echo "Packaged Desklamp $VERSION in dist/"
