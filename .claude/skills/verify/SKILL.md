---
name: verify
description: Verify the Desklamp macOS menu bar keep-awake app (AppKit NSStatusItem, XcodeGen). Use after changing anything under Desklamp/ to confirm it builds, launches, holds a PreventUserIdleSystemSleep assertion, shows its menu, and releases the assertion on quit.
---

# verify: Desklamp

Surface: macOS menu bar app (LSUIElement, no Dock icon, no window). Driver: `.claude/skills/verify/run.sh`. Evidence dir: `/tmp/verify-desklamp-<hash>/` (printed by `up`).

## Launch
Single-instance by design: `up` records the path of any other running Desklamp (e.g. the installed `/Applications/Desklamp.app`), quits it, and `down` relaunches it. All assertion checks are scoped to the test pid.

`.claude/skills/verify/run.sh up` regenerates the project (`xcodegen generate`), builds scheme `Desklamp` Debug into the evidence dir's DerivedData, and launches that exact `.app` with `-activateOnLaunch YES`. Prints `UP pid=...`.

## Doctor
`run.sh doctor` confirms the recorded pid is alive, is our build, and that `pmset -g assertions` lists `PreventUserIdleSystemSleep` for that pid. Prints `OK pid=...: <assertion line>`.

## Drive
Interaction model: plain left-click toggles keep-awake; right-click or Control-click opens the menu.
1. `run.sh toggle` left-clicks the status item (System Events, `click menu bar item 1 of menu bar 2`) and prints `ASSERTIONS <n>` (count of `(Desklamp)` lines in `pmset -g assertions`). Run twice: after `up` (starts active) expect 0, then 2 (system + display). Both directions are the evidence.
2. `run.sh menu` Control-clicks the item via a tiny CGEvent helper (compiled with `swiftc` into the evidence dir), prints the menu item names, then presses Esc. Expect `Stop Keeping Awake` (or `Keep Awake`), `Keep Awake For`, `Allow Display Sleep`, `Launch at Login`, `Quit Desklamp`, with `missing value` for the two separators.
3. Known limits: System Events `perform action "AXShowMenu"` returns without opening anything (the item has no menu attached until a right/ctrl click), so do not use it. Both scripts need Accessibility permission for the calling terminal; exit 2 / `BLOCKED` means it is missing. Report it; do not change system settings, and fall back to the `doctor` evidence only. `screencapture` does not render the open menu, so the AX item list is the menu evidence.

## Evidence
`assertions.active.txt`, `assertions.after.txt`, `build.log`, git status before/after.

## Gotchas
- Debug-only launch arg `-activateOnLaunch YES` is how activation is driven headlessly; the real path is left-clicking the status item.
- Use `open -n` of the DerivedData build, never a stale copy in /Applications; `down` kills only the recorded pid.
- `*.xcodeproj` is gitignored and regenerated each run. Tests: `xcodebuild -project Desklamp.xcodeproj -scheme Desklamp test` (not part of this flow).
- The app is sandboxed and ad-hoc signed; no side effects beyond the power assertion.

## Teardown
`run.sh down` kills the recorded pid, checks the process is gone, `pmset -g assertions` has no Desklamp entry, and git status is unchanged.
