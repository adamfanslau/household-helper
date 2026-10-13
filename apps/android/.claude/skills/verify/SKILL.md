---
name: verify
description: Build, install, launch and drive the Household Helper Android app (dev flavor) on the Pixel_10_Pro emulator with adb and uiautomator, snapshot it and assert on the tree (scoped to apps/android).
---

# Verifying apps/android changes

Prereqs: local stack up (`scripts/dev/stack.sh up`; the app reaches it on the device loopback through `adb reverse`, set up by `android.sh avd up|status|launch`), AVD
`Pixel_10_Pro` running (`scripts/dev/android.sh avd up`). All paths from the repo root.

## Inner loop (≈ 1–2 min after the first build)

```bash
scripts/dev/android.sh build                       # ./gradlew :app:installDevDebug, prints BUILD OK
scripts/dev/android.sh launch alice                # force-stop + start with HH_UITEST_USER (dev flavor)
scripts/dev/android.sh tree | grep list.item       # resource-id | text | content-desc | class | bounds
scripts/dev/android.sh tap tab.settings
scripts/dev/snap.sh android settings               # .dev/shots/settings/{screen.png,tree.txt,log.txt}
scripts/dev/assert.sh tree settings 'settings.signOut'
```

Test tags appear as `resource-id` only because the root sets `testTagsAsResourceId = true`.
Tap by tag, assert from the tree / API / `android.sh log` (logcat tag `HH`), read `screen.png`
for layout questions. `launch none` relaunches like a tap on the launcher icon.
Dark mode: `android.sh night on|off`; font scale: `android.sh fontscale 2.0` (back to `1.0`).

## Identifiers (same vocabulary as iOS A11y.swift)

`signin.dev.alice|bob`, `signin.google`, `onboarding.mode.create|join`, `onboarding.input`,
`onboarding.submit`, `tab.list|shops|settings`, `list.section.<name>`, `list.item.<name>`,
`list.bought.toggle`, `settings.email`, `settings.household.<name>`, `settings.signOut`.

## Gotchas

- Play-Store AVD: no `adb root`; read state via logcat and the API, not the filesystem.
- `adb shell input text` can't type spaces directly; the helper encodes them (`%s`).
- First Gradle build is minutes (dependency download); keep the daemon (never `--stop`).
- The dev flavor's `google-services.json` is fabricated; Firebase Auth talks to the emulator only.
- Seed and users: see the `dev-stack` skill (alice owns Mock Household, bob The Neighbors, carol none).
