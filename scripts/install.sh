#!/bin/bash
# Build Release and install to /Applications (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."
NEW=/Applications/.Awake.app.new
OLD=/Applications/.Awake.app.old
trap 'rm -rf "$NEW"' EXIT
xcodegen generate
xcodebuild -scheme Awake -configuration Release -derivedDataPath build -quiet build
pkill -x Awake || true
for i in $(seq 1 20); do pgrep -x Awake >/dev/null || break; sleep 0.25; done
if pgrep -x Awake >/dev/null; then echo "Awake did not quit; aborting" >&2; exit 1; fi
rm -rf "$NEW" "$OLD"
ditto build/Build/Products/Release/Awake.app "$NEW"
[ -d /Applications/Awake.app ] && mv /Applications/Awake.app "$OLD"
if ! mv "$NEW" /Applications/Awake.app; then
  [ -d "$OLD" ] && mv "$OLD" /Applications/Awake.app
  echo "install failed; previous version restored" >&2
  exit 1
fi
rm -rf "$OLD"
open /Applications/Awake.app
