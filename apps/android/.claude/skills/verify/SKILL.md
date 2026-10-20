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
scripts/dev/android.sh wait list.item.Milk 20      # poll the tree until the tag exists (after launch/animations)
scripts/dev/android.sh tap list.add; scripts/dev/android.sh wait list.input      # floating + → add sheet
scripts/dev/android.sh type "Chi"; scripts/dev/android.sh tap "list.suggestion.Chicken breast"   # hints fill qty + shop
scripts/dev/android.sh tap list.shop; scripts/dev/android.sh tap list.shop.new; scripts/dev/android.sh tap list.newShop
scripts/dev/android.sh type "Lidl"; scripts/dev/android.sh key KEYCODE_ENTER     # Done submits (never `back`: it closes the sheet)
scripts/dev/android.sh wait "list.item.Chicken breast"
scripts/dev/snap.sh android add-item               # .dev/shots/add-item/{screen.png,tree.txt,log.txt}
scripts/dev/assert.sh api alice /v1/households/11111111-1111-4111-8111-111111111111/items '.[] | select(.name=="Oat milk") | .shop_id == null'
```

Driver commands (`scripts/dev/android.sh`): `tree`, `tap <tag|x y>`, `taptext "<text>"` (snackbar actions,
dialog buttons), `longpress <tag>` (opens the row sheet), `swipe left|right|up|down [tag]` (600 ms horizontal
swipes; left = delete, right = bought), `type "text"`, `clear` (empties the focused field — tap the field first),
`key <KEYCODE> [n]`, `back`, `wait <tag> [secs]` / `waittext "<text>" [secs]`, `open householdhelper://…`
(deep link into the running app), `night yes|no`, `fontscale 2.0` (back to `1.0`), `log [n]` (logcat tag `HH`),
`unit`, `uitest` (Compose `SmokeTest`, needs a fresh seed: `stack.sh reset` first).

Push (the dev flavor never talks to FCM; the handling is driven with an intent extra):

```bash
scripts/dev/android.sh taptext Allow            # POST_NOTIFICATIONS prompt on the first launch with a household (API 33+)
adb -s emulator-5554 shell am start -n com.householdhelper.app.dev/com.householdhelper.app.MainActivity \
  --es HH_FAKE_PUSH "'<household_id>~<title>~<body>'"     # single quotes inside: adb's shell splits on spaces
scripts/dev/android.sh log 10 | grep -E 'suppressed|posted'  # current household on screen → suppressed
adb -s emulator-5554 shell cmd statusbar expand-notifications; scripts/dev/android.sh taptext "<body>"   # tap → switches household
adb -s emulator-5554 shell am start -n … --es household_id <id>   # what a background-notification tap delivers (cold start too)
```

Assert from the tree / API / log, read `screen.png` only for layout questions. `launch none` relaunches
like a tap on the launcher icon (session + household must survive).

## Identifiers (same vocabulary as iOS A11y.swift)

`signin.dev.alice|bob`, `signin.google`, `onboarding.sheet`, `onboarding.mode.create|join`, `onboarding.input`,
`onboarding.submit`, `tab.list|shops|settings`, `list`, `list.input`, `list.add`, `list.section.<name>`,
`list.item.<name>`, `list.bought.toggle`, `list.bought.menu`, `list.bought.clear`, `list.share`, `list.empty`,
`list.addSheet`, `list.quantity`, `list.shop`, `list.shop.none|<name>|new`, `list.newShop`, `list.submit`, `list.suggestion.<name>`,
`item.sheet`, `item.move.<shop>|Unsorted`, `item.edit`, `item.toggle`, `item.delete`, `edit.name`, `edit.quantity`,
`edit.save`, `shops.input`, `shops.add`, `shops.row.<name>`, `shops.delete.confirm`,
`shop.row.<name>`, `shop.menu`, `shop.rename.input`, `settings.name`, `settings.email`, `settings.inviteCode`,
`settings.share`, `settings.regenerate`, `settings.household.<name>`, `settings.addHousehold`, `settings.rename.input`,
`settings.notifications`, `settings.signOut`, `settings.signOut.confirm`, `connection.reconnecting`, `snackbar`.

Deep links: `householdhelper://list | shops | shops/<uuid> | settings | join/<CODE>`.

## Gotchas

- Play-Store AVD: no `adb root`; read state via logcat and the API, not the filesystem.
- Sheets, dialogs and dropdown menus are separate windows: their tags show up only because each one
  carries `Modifier.exposeTestTags()` (ui/Semantics.kt). Add it to any new sheet/dialog/popup.
- The keyboard stays open after `type`; on the list screen `back` once before tapping the lower half,
  but inside the add sheet `back` dismisses the sheet: use `key KEYCODE_ENTER` (Done submits) instead.
- Products are household-wide (typing hints with last quantity/shop); shop detail shows the shop's open items.
- Shopping is two steps: tapping a row = in the basket (filled green tick, sinks to the bottom of its shop,
  description "in basket"); the section header then shows `list.checkout.<title>` and the shop screen a
  `shop.checkout` bar; checkout turns the basket into bought. Swipe right and the sheet's "Mark bought" go
  straight to bought; the sheet also has `item.basket` ("In the basket" / "Take out of basket").
- `uiautomator dump` waits for an idle UI; `wait`/`waittext` poll instead of fixed sleeps. `taptext` must
  run while the snackbar (5 s undo grace) is still showing.
- Settings is a scrolling list; `swipe up` before `settings.signOut` at large font scales.
- `adb shell input text` can't type spaces directly; the helper encodes them (`%s`).
- Configuration changes (night mode, font scale) recreate the Activity; deep-link intents are handled only
  on a fresh start (`savedInstanceState == null`), so the current tab survives them.
- First Gradle build is minutes (dependency download); keep the daemon (never `--stop`).
- The dev flavor's `google-services.json` is fabricated; Firebase Auth talks to the emulator only and
  FCM auto-init is off in `src/dev/AndroidManifest.xml` (Installations would reject the fake key).
  Google sign-in (`signin.google`) is disabled in dev: it needs the prod flavor's Web client id.
- `adb shell pm clear com.householdhelper.app.dev` resets the notification permission (and the session).
- Seed and users: see the `dev-stack` skill (alice owns Mock Household, bob The Neighbors, carol none).
