#!/bin/bash
# Build Release and install to /Applications (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."
NEW=/Applications/.Lamplight.app.new
OLD=/Applications/.Lamplight.app.old
trap 'rm -rf "$NEW"' EXIT

# Quit a running app by process name; fail if it won't exit.
quit_app() {
  pkill -x "$1" || true
  for i in $(seq 1 20); do pgrep -x "$1" >/dev/null || break; sleep 0.25; done
  if pgrep -x "$1" >/dev/null; then echo "$1 did not quit; aborting" >&2; exit 1; fi
}

xcodegen generate
xcodebuild -project Lamplight.xcodeproj -scheme Lamplight -configuration Release -derivedDataPath build -quiet build
quit_app Lamplight
rm -rf "$NEW" "$OLD"
ditto build/Build/Products/Release/Lamplight.app "$NEW"
[ -d /Applications/Lamplight.app ] && mv /Applications/Lamplight.app "$OLD"
if ! mv "$NEW" /Applications/Lamplight.app; then
  [ -d "$OLD" ] && mv "$OLD" /Applications/Lamplight.app
  echo "install failed; previous version restored" >&2
  exit 1
fi
rm -rf "$OLD"

# Lamplight was previously named Awake; retire that build only now that Lamplight is in place.
quit_app Awake
rm -rf /Applications/Awake.app

open /Applications/Lamplight.app
