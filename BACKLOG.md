# Backlog

## 2026-10-10

- [ ] (carried) App icon = Blender draft C, exactly (design/app-icon/draft-C.png). Render final at 256 samples via `awake_icon.py --variant Cdraft` (verified to reproduce draft C, mean diff 0.135/255), export passes, build `AppIcon.icon` (Icon Composer), wire into project.yml + fallback .appiconset, verify, review, install.
- [ ] (carried) Final app name — "Awake" is a placeholder (only in project.yml + CFBundleDisplayName). Strawman: "Midnight Oil" (burning the midnight oil = lamp + staying up late + the aging beam). Availability unchecked.
- [ ] (parked) Publishing: needs Apple Developer Program ($99/yr) for signing + notarization; check name collisions on App Store/GitHub.
- [ ] (parked) Live check of Dimmer (3h) / Flicker (6h) lamp stages and the menu-open highlighted icon in the real menu bar.
- [ ] (parked) verify-gate hook fires on regenerated, untracked Awake.xcodeproj — consider ignoring gitignored paths.
