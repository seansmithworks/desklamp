#!/bin/bash
# Build Release and install to /Applications (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -scheme Awake -configuration Release -derivedDataPath build -quiet build
pkill -x Awake || true
for i in $(seq 1 20); do pgrep -x Awake >/dev/null || break; sleep 0.25; done
rm -rf /Applications/Awake.app
ditto build/Build/Products/Release/Awake.app /Applications/Awake.app
open /Applications/Awake.app
