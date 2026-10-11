#!/bin/bash
# Mechanical verify steps for Lamplight (menu bar keep-awake app). Usage: run.sh up|doctor|toggle|menu|down
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
HASH="$(printf '%s' "$REPO" | shasum | cut -c1-8)"
EV="/tmp/verify-lamplight-$HASH"
APP="$EV/DerivedData/Build/Products/Debug/Lamplight.app"
BIN="$APP/Contents/MacOS/Lamplight"
PIDF="$EV/pid"
mkdir -p "$EV"

ours_pid() { pgrep -f "$BIN" | head -1; }

# Relaunch apps recorded by `up`; the record is cleared only after every relaunch succeeds.
relaunch_prior() {
  [ -s "$EV/prior-apps" ] || return 0
  local ok=1 a
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    if open "$a"; then echo "RELAUNCHED $a"; else ok=0; fi
  done < "$EV/prior-apps"
  [ "$ok" = 1 ] && : > "$EV/prior-apps"
  return 0
}

case "${1:-}" in
up)
  ( cd "$REPO" && git status --porcelain ) > "$EV/git-status.before"
  [ -n "$(ours_pid)" ] && { echo "FAIL: our Lamplight already running (pid $(ours_pid)); run down first"; exit 1; }
  # Single-instance by design: record and quit any other Lamplight; `down` (or this trap on failure) relaunches it.
  # The record is only appended to (deduped), never truncated, so an unconsumed record survives a retried `up`.
  UP_OK=0
  trap '[ "$UP_OK" = 1 ] || relaunch_prior' EXIT
  for q in $(pgrep -x Lamplight); do
    path="$(ps -p "$q" -o command= | sed 's#/Contents/MacOS/Lamplight.*##')"
    grep -qxF "$path" "$EV/prior-apps" 2>/dev/null || echo "$path" >> "$EV/prior-apps"
    kill "$q"
  done
  for i in $(seq 1 20); do pgrep -x Lamplight >/dev/null || break; sleep 0.25; done
  pgrep -x Lamplight >/dev/null && { echo "FAIL: could not quit the running Lamplight"; exit 1; }
  ( cd "$REPO" && xcodegen generate ) > "$EV/xcodegen.log" 2>&1 || { echo "FAIL: xcodegen, see $EV/xcodegen.log"; exit 1; }
  # VERIFY_FORCE_BUILD_FAIL=1 simulates a build failure (for testing this script's recovery path).
  ( [ -z "${VERIFY_FORCE_BUILD_FAIL:-}" ] && cd "$REPO" && xcodebuild -project Lamplight.xcodeproj -scheme Lamplight -configuration Debug -derivedDataPath "$EV/DerivedData" build ) > "$EV/build.log" 2>&1
  grep -q "BUILD SUCCEEDED" "$EV/build.log" || { echo "FAIL: build, see $EV/build.log"; exit 1; }
  open -n "$APP" --args -activateOnLaunch YES
  for i in $(seq 1 20); do [ -n "$(ours_pid)" ] && break; sleep 0.5; done
  P="$(ours_pid)"; [ -n "$P" ] || { echo "FAIL: Lamplight did not start"; exit 1; }
  echo "$P" > "$PIDF"; sleep 1
  UP_OK=1
  echo "UP pid=$P evidence=$EV"
  ;;
doctor)
  P="$(cat "$PIDF" 2>/dev/null)"
  [ -n "$P" ] && kill -0 "$P" 2>/dev/null || { echo "FAIL: recorded pid not alive"; exit 1; }
  ps -p "$P" -o command= | grep -q "$BIN" || { echo "FAIL: pid $P is not our build"; exit 1; }
  pmset -g assertions > "$EV/assertions.active.txt"
  L="$(grep -E "pid $P\(Lamplight\).*PreventUserIdleSystemSleep" "$EV/assertions.active.txt" | head -1)"
  [ -n "$L" ] || { echo "FAIL: no PreventUserIdleSystemSleep for pid $P"; exit 1; }
  echo "OK pid=$P: $L"
  ;;
toggle)
  # Plain left-click on the status item: toggles keep-awake. Prints the Lamplight assertion count after (0 = off).
  osascript -e 'tell application "System Events" to tell process "Lamplight" to click menu bar item 1 of menu bar 2' > "$EV/osascript.log" 2>&1 \
    || { echo "BLOCKED: click failed: $(cat "$EV/osascript.log")"; exit 2; }
  sleep 1; echo "ASSERTIONS $(pmset -g assertions | grep -c "pid $(cat "$PIDF")(Lamplight)")"
  ;;
menu)
  # Control-click on the status item (AXShowMenu does nothing here), list the menu items, then close it.
  cat > "$EV/ctrlclick.swift" <<'SW'
import CoreGraphics
import Foundation
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!
    e.flags = .maskControl
    e.post(tap: .cghidEventTap)
    usleep(80000)
}
SW
  swiftc -o "$EV/ctrlclick" "$EV/ctrlclick.swift" 2>"$EV/swiftc.log" || { echo "FAIL: swiftc, see $EV/swiftc.log"; exit 1; }
  POS="$(osascript -e 'tell application "System Events" to tell process "Lamplight" to get {position, size} of menu bar item 1 of menu bar 2' 2>"$EV/osascript.log")" \
    || { echo "BLOCKED: $(cat "$EV/osascript.log")"; exit 2; }
  X="$(echo "$POS" | awk -F', ' '{print $1+$3/2}')"; Y="$(echo "$POS" | awk -F', ' '{print $2+$4/2}')"
  "$EV/ctrlclick" "$X" "$Y"
  # The menu attaches asynchronously; wait (bounded) for System Events to see it.
  ITEMS=""
  for i in $(seq 1 15); do
    ITEMS="$(osascript -e 'tell application "System Events" to tell process "Lamplight" to get name of every menu item of menu 1 of menu bar item 1 of menu bar 2' 2>/dev/null)" && break
    ITEMS=""; sleep 0.3
  done
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
  [ -n "$ITEMS" ] || { echo "FAIL: menu did not open"; exit 1; }
  echo "$ITEMS"
  ;;
down)
  RC=0
  P="$(cat "$PIDF" 2>/dev/null)"
  if [ -n "$P" ] && ps -p "$P" -o command= 2>/dev/null | grep -q "$BIN"; then
    kill "$P"; for i in $(seq 1 20); do kill -0 "$P" 2>/dev/null || break; sleep 0.25; done
  fi
  [ -z "$(ours_pid)" ] || { echo "FAIL: still running"; RC=1; }
  pmset -g assertions > "$EV/assertions.after.txt"
  if grep -q "pid ${P:-0}(Lamplight)" "$EV/assertions.after.txt"; then echo "FAIL: Lamplight assertion remains"; RC=1; fi
  # Always restore the user's app, whatever the checks said; exit code still reflects them.
  relaunch_prior
  ( cd "$REPO" && git status --porcelain ) > "$EV/git-status.after"
  if [ "$RC" = 0 ]; then
    diff -q "$EV/git-status.before" "$EV/git-status.after" >/dev/null 2>&1 && echo "DOWN clean, no drift, no Lamplight assertions" || echo "DOWN ok, but git status drift (see $EV/git-status.*)"
  fi
  exit "$RC"
  ;;
*) echo "usage: run.sh up|doctor|toggle|menu|down"; exit 64;;
esac
