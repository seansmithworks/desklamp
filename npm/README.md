# Desklamp

A macOS menu bar app that keeps your Mac awake. Requires macOS 14 or later.

## Install

```
npx @seansmithworks/desklamp
```

The installer:

1. Downloads `Desklamp.zip` and `SHA256SUMS` from the [latest GitHub release](https://github.com/seansmithworks/desklamp/releases/latest).
2. Verifies the zip's SHA-256 checksum.
3. Unpacks it, quits a running Desklamp, and installs to `/Applications` (the previous version is restored if the swap fails).
4. Opens Desklamp.

Prefer not to run an installer? Download the zip or DMG from the [releases page](https://github.com/seansmithworks/desklamp/releases) and drag Desklamp to Applications.

## Gatekeeper

Desklamp is ad-hoc signed and not notarized. A file downloaded by Node has no quarantine attribute, so macOS will not show a Gatekeeper prompt for an app installed this way. A copy downloaded in a browser (zip or DMG) does carry quarantine, and you will need to right-click the app and choose Open the first time.

## Privacy

No permissions. No network. Nothing collected.

The app itself never touches the network. The installer's only network access is downloading the release from GitHub.

Source and issues: https://github.com/seansmithworks/desklamp
