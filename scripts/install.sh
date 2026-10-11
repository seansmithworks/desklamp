#!/bin/bash
# Build Release and install to /Applications (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."
NEW=/Applications/.Desklamp.app.new
OLD=/Applications/.Desklamp.app.old
trap 'rm -rf "$NEW"' EXIT

# Quit a running app by process name; fail if it won't exit.
quit_app() {
  pkill -x "$1" || true
  for i in $(seq 1 20); do pgrep -x "$1" >/dev/null || break; sleep 0.25; done
  if pgrep -x "$1" >/dev/null; then echo "$1 did not quit; aborting" >&2; exit 1; fi
}

xcodegen generate
xcodebuild -project Desklamp.xcodeproj -scheme Desklamp -configuration Release -derivedDataPath build -quiet build
quit_app Desklamp
rm -rf "$NEW" "$OLD"
ditto build/Build/Products/Release/Desklamp.app "$NEW"
[ -d /Applications/Desklamp.app ] && mv /Applications/Desklamp.app "$OLD"
if ! mv "$NEW" /Applications/Desklamp.app; then
  [ -d "$OLD" ] && mv "$OLD" /Applications/Desklamp.app
  echo "install failed; previous version restored" >&2
  exit 1
fi
rm -rf "$OLD"

# Desklamp was previously named Lamplight (and before that Awake); retire those builds only now that Desklamp is in place.
quit_app Lamplight
rm -rf /Applications/Lamplight.app
quit_app Awake
rm -rf /Applications/Awake.app

open /Applications/Desklamp.app
