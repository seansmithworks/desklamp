---
name: verify
description: Verify the Awake macOS menu bar keep-awake app (SwiftUI MenuBarExtra, XcodeGen). Use after changing anything under Awake/ to confirm it builds, launches, holds a PreventUserIdleSystemSleep assertion, shows its menu, and releases the assertion on quit.
---

# verify: Awake

Surface: macOS menu bar app (LSUIElement, no Dock icon, no window). Driver: `.claude/skills/verify/run.sh`. Evidence dir: `/tmp/verify-awake-<hash>/` (printed by `up`).

## Launch
`.claude/skills/verify/run.sh up` regenerates the project (`xcodegen generate`), builds scheme `Awake` Debug into the evidence dir's DerivedData, and launches that exact `.app` with `-activateOnLaunch YES`. Prints `UP pid=...`.

## Doctor
`run.sh doctor` confirms the recorded pid is alive, is our build, and that `pmset -g assertions` lists `PreventUserIdleSystemSleep` for that pid. Prints `OK pid=...: <assertion line>`.

## Drive
1. `run.sh shot` clicks the menu bar item (`click menu bar item 1 of menu bar 2` via System Events) and screencaptures the top-right 700x420 to `<evidence>/menu-open.png`. Pass a path to save elsewhere (e.g. `docs/menu-open.png`).
2. Read the screenshot: the menu should be open under the Awake icon, listing the activate toggle, duration options and quit. A closed menu or an empty strip means the click did not land.
3. Known limit (observed 2026-10-10): the AX click succeeds and the menu items are readable (`Stop Keeping Awake, Keep Awake For, Allow Display Sleep, Launch at Login, Quit Awake`), but `screencapture` did not render the open menu, so the PNG shows the closed menu bar. Treat the AX item list as the menu evidence and do not commit a PNG that lacks the dropdown.
4. Exit code 2 / `BLOCKED` means the terminal lacks Accessibility permission. Report it; do not change system settings, and fall back to the `doctor` evidence only.

## Evidence
`assertions.active.txt`, `assertions.after.txt`, `build.log`, `menu-open.png`, git status before/after.

## Gotchas
- Debug-only launch arg `-activateOnLaunch YES` is how activation is driven headlessly; the real path is clicking the menu toggle.
- Use `open -n` of the DerivedData build, never a stale copy in /Applications; `down` kills only the recorded pid.
- `*.xcodeproj` is gitignored and regenerated each run. Tests: `xcodebuild -scheme Awake test` (not part of this flow).
- The app is sandboxed and ad-hoc signed; no side effects beyond the power assertion.

## Teardown
`run.sh down` kills the recorded pid, checks the process is gone, `pmset -g assertions` has no Awake entry, and git status is unchanged.
