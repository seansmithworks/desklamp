#!/bin/bash
# Mechanical verify steps for Awake (menu bar keep-awake app). Usage: run.sh up|doctor|shot|down
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
HASH="$(printf '%s' "$REPO" | shasum | cut -c1-8)"
EV="/tmp/verify-awake-$HASH"
APP="$EV/DerivedData/Build/Products/Debug/Awake.app"
BIN="$APP/Contents/MacOS/Awake"
PIDF="$EV/pid"
mkdir -p "$EV"

ours_pid() { pgrep -f "$BIN" | head -1; }

case "${1:-}" in
up)
  ( cd "$REPO" && git status --porcelain ) > "$EV/git-status.before"
  [ -n "$(ours_pid)" ] && { echo "FAIL: our Awake already running (pid $(ours_pid)); run down first"; exit 1; }
  ( cd "$REPO" && xcodegen generate ) > "$EV/xcodegen.log" 2>&1 || { echo "FAIL: xcodegen, see $EV/xcodegen.log"; exit 1; }
  ( cd "$REPO" && xcodebuild -scheme Awake -configuration Debug -derivedDataPath "$EV/DerivedData" build ) > "$EV/build.log" 2>&1
  grep -q "BUILD SUCCEEDED" "$EV/build.log" || { echo "FAIL: build, see $EV/build.log"; exit 1; }
  open -n "$APP" --args -activateOnLaunch YES
  for i in $(seq 1 20); do [ -n "$(ours_pid)" ] && break; sleep 0.5; done
  P="$(ours_pid)"; [ -n "$P" ] || { echo "FAIL: Awake did not start"; exit 1; }
  echo "$P" > "$PIDF"; sleep 1
  echo "UP pid=$P evidence=$EV"
  ;;
doctor)
  P="$(cat "$PIDF" 2>/dev/null)"
  [ -n "$P" ] && kill -0 "$P" 2>/dev/null || { echo "FAIL: recorded pid not alive"; exit 1; }
  ps -p "$P" -o command= | grep -q "$BIN" || { echo "FAIL: pid $P is not our build"; exit 1; }
  pmset -g assertions > "$EV/assertions.active.txt"
  L="$(grep -E "pid $P\(Awake\).*PreventUserIdleSystemSleep" "$EV/assertions.active.txt" | head -1)"
  [ -n "$L" ] || { echo "FAIL: no PreventUserIdleSystemSleep for pid $P"; exit 1; }
  echo "OK pid=$P: $L"
  ;;
shot)
  # Opens the menu via System Events (needs Accessibility permission for the calling terminal) and captures top-right.
  OUT="${2:-$EV/menu-open.png}"
  osascript -e 'tell application "System Events" to tell process "Awake" to click menu bar item 1 of menu bar 2' > "$EV/osascript.log" 2>&1 \
    || { echo "BLOCKED: click failed: $(cat "$EV/osascript.log")"; exit 2; }
  sleep 1
  W="$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)' 2>/dev/null || echo 1512)"
  screencapture -x -R "$((W-700)),0,700,420" "$OUT" && echo "SHOT $OUT"
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
  ;;
down)
  P="$(cat "$PIDF" 2>/dev/null)"
  if [ -n "$P" ] && ps -p "$P" -o command= 2>/dev/null | grep -q "$BIN"; then
    kill "$P"; for i in $(seq 1 20); do kill -0 "$P" 2>/dev/null || break; sleep 0.25; done
  fi
  [ -z "$(ours_pid)" ] || { echo "FAIL: still running"; exit 1; }
  pmset -g assertions > "$EV/assertions.after.txt"
  if grep -q "(Awake)" "$EV/assertions.after.txt"; then echo "FAIL: Awake assertion remains"; exit 1; fi
  ( cd "$REPO" && git status --porcelain ) > "$EV/git-status.after"
  diff -q "$EV/git-status.before" "$EV/git-status.after" >/dev/null 2>&1 && echo "DOWN clean, no drift, no Awake assertions" || echo "DOWN ok, but git status drift (see $EV/git-status.*)"
  ;;
*) echo "usage: run.sh up|doctor|shot [out.png]|down"; exit 64;;
esac
