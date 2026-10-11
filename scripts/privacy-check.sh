#!/bin/bash
# Privacy gate. Fails (non-zero) if shipped artifacts leak local identity, or if tracked files hold secrets.
#   privacy-check.sh              scan dist/ (zips, DMGs) and the npm pack tarball
#   privacy-check.sh PATH...      scan the given files/dirs/.zip/.dmg instead
#   privacy-check.sh --repo       scan tracked files and history for secrets
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail=0
USER_NAME=${USER:-$(id -un)}
HOST=$(scutil --get LocalHostName 2>/dev/null || true)

report() { echo "PRIVACY LEAK: $1" >&2; fail=1; }

# Scan every file under a directory for identity leaks.
scan_dir() {
  local dir=$1 label=$2 hits
  hits=$(grep -raoE '/Users/[^[:space:]"]{0,60}|/private/tmp[^[:space:]"]{0,60}' "$dir" 2>/dev/null || true)
  [ -n "$hits" ] && report "$label contains local paths:" && echo "$hits" | sort -u | head -10 >&2
  hits=$(grep -raoE "/$USER_NAME([/[:space:]\"'\\]|$)" "$dir" 2>/dev/null || true)
  [ -n "$hits" ] && report "$label contains username '$USER_NAME' as a path segment:" && echo "$hits" | sort -u | head -10 >&2
  if [ -n "$HOST" ]; then
    hits=$(grep -raoiF "$HOST" "$dir" 2>/dev/null || true)
    [ -n "$hits" ] && report "$label contains hostname '$HOST'"
  fi
  hits=$(grep -raoE '[A-Za-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}' "$dir" 2>/dev/null | grep -viE 'noreply|@[0-9]+x\.(png|jpe?g|gif|pdf|svg|heic|car)$' || true)
  [ -n "$hits" ] && report "$label contains email addresses:" && echo "$hits" | sort -u | head -10 >&2
  return 0
}

scan_target() {
  local t=$1 n out
  n=$(mktemp -d "$WORK/t.XXXXXX")
  case "$t" in
    *.zip) ditto -x -k "$t" "$n"; scan_dir "$n" "$t" ;;
    *.dmg)
      out=$(hdiutil attach -readonly -nobrowse -noverify -noautoopen -mountrandom "$WORK" "$t")
      MOUNT=$(echo "$out" | awk -F'\t' 'END {print $NF}' | sed 's/^ *//')
      [ -d "$MOUNT" ] || { echo "privacy-check: could not mount $t" >&2; exit 2; }
      scan_dir "$MOUNT" "$t"
      hdiutil detach -quiet "$MOUNT"; MOUNT="" ;;
    *) scan_dir "$t" "$t" ;;
  esac
  # The DMG file itself is compressed, so only its mounted contents are meaningful.
}

scan_repo() {
  if command -v gitleaks >/dev/null; then
    echo "privacy-check: repo mode = gitleaks ($(gitleaks version))"
    gitleaks git --no-banner --redact --log-opts=--all . || { echo "PRIVACY LEAK: gitleaks found secrets in git history" >&2; fail=1; }
    return
  fi
  echo "privacy-check: repo mode = grep fallback (gitleaks not installed)"
  local files hits
  files=$(git ls-files)
  hits=$(echo "$files" | grep -E '(^|/)(\.env[^/]*|\.npmrc|[^/]*\.(pem|p12|key|mobileprovision))$' || true)
  [ -n "$hits" ] && report "sensitive filenames tracked:" && echo "$hits" >&2
  hits=$(echo "$files" | tr '\n' '\0' | xargs -0 grep -IlE 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]+|gh[po]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+|xox[bp]-[A-Za-z0-9-]+|sk_live_[A-Za-z0-9]+|BEGIN [A-Z ]*PRIVATE KEY|_auth[T]oken' 2>/dev/null || true)
  [ -n "$hits" ] && report "secret-shaped strings in (values not shown):" && echo "$hits" >&2
  return 0
}

if [ "${1:-}" = "--repo" ]; then
  scan_repo
else
  if [ $# -gt 0 ]; then
    targets=("$@")
  else
    targets=()
    for f in dist/*.zip dist/*.dmg; do [ -e "$f" ] && targets+=("$f"); done
    [ ${#targets[@]} -gt 0 ] || { echo "privacy-check: nothing in dist/ to scan" >&2; exit 2; }
    if [ -f npm/package.json ]; then
      mkdir "$WORK/npm"
      (cd npm && npm pack --silent --pack-destination "$WORK/npm" >/dev/null)
      mkdir "$WORK/npm-x"; tar -xzf "$WORK"/npm/*.tgz -C "$WORK/npm-x"
      targets+=("$WORK/npm-x")
    fi
  fi
  for t in "${targets[@]}"; do
    [ -e "$t" ] || { echo "privacy-check: target not found: $t" >&2; exit 2; }
  done
  for t in "${targets[@]}"; do scan_target "$t"; done
fi

if [ "$fail" -ne 0 ]; then
  echo "privacy-check: FAILED" >&2
  exit 1
fi
echo "privacy-check: passed"
