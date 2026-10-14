---
name: verify
description: Build, install, launch and drive the Household Helper iOS app on a named simulator with AXe, snapshot it and assert on the accessibility tree (scoped to apps/ios).
---

# Verifying apps/ios changes

Prereqs: local stack up (`scripts/dev/stack.sh up`), AXe installed. All paths from the repo root.
Never pass `booted` to simctl: two simulators may be up. Resolve a UDID once:

```bash
U=$(scripts/dev/sim.sh resolve "iPhone 17")      # 89850DF1-19BE-4DAF-92D5-B6411AF061A4 on iOS 26.3
scripts/dev/sim.sh boot "$U"
```

## Inner loop (≈ 1–3 min after the first build)

```bash
scripts/dev/ios.sh gen                     # only after editing apps/ios/project.yml
scripts/dev/ios.sh build                   # Debug = emulator auth + localhost API baked in; prints BUILD OK
scripts/dev/ios.sh install "$U"
scripts/dev/ios.sh launch "$U" alice householdhelper://list   # auto sign-in as alice (dev builds only)
scripts/dev/ios.sh tree "$U" | grep list.item               # id | label | type | x,y,w,h
scripts/dev/ios.sh label "$U" Settings                       # tabs have no identifier: tap by label
scripts/dev/snap.sh ios "$U" settings                        # .dev/shots/settings/{screen.png,tree.txt,log.txt}
scripts/dev/assert.sh tree settings 'settings.signOut'
```

Push (dev builds never talk to APNs/FCM; the handling is driven with `simctl push`):

```bash
scripts/dev/ios.sh allow "$U"                  # the permission alert shows on the first launch with a household
scripts/dev/ios.sh push "$U" <household_id> "Mock Household" "Bob added Coffee"   # same keys hh-api sends
scripts/dev/ios.sh log "$U" 20 | grep push    # "suppressed push for the current household" when it is on screen
scripts/dev/ios.sh tap "$U" 201 70            # the banner is SpringBoard's (not in the app tree): tap its centre within ~3 s
```

Assert from the tree, the API (`assert.sh api alice /v1/… '<jq>'`) and the log before reading
`screen.png`; read the PNG for layout questions only. `launch "$U" none` relaunches like a tap on
the home screen (keeps the Firebase session and the selected household) — test it after any
config change. Light/dark and text size: `ios.sh appearance "$U" dark`, `ios.sh textsize "$U" ax5`.

## Identifiers (Support/A11y.swift; same vocabulary as Android testTags)

`signin.dev.alice|bob`, `onboarding.mode` (segmented: tap by label "Create"/"Join"), `onboarding.input`,
`onboarding.submit`, tabs by label (`ios.sh label "$U" List|Shops|Settings`), `list.item.<name>`, `list.bought.toggle`,
`list.input`, `list.add`, `list.item.<name>` (tap = toggle), `list.item.<name>.bought|.delete` (swipe buttons),
`list.bought.toggle`, `list.bought.menu`, `list.undo`, `edit.name|quantity|save`, `shops.input`, `shops.add`,
`shops.row.<name>`, `shop.input`, `shop.add`, `shop.menu`, `shop.row.<name>` (text), `shop.toList.<name>` (row button),
`settings.inviteCode`, `settings.share`, `settings.regenerate`, `settings.addHousehold`,
`settings.household.<name>`, `settings.signOut`, `settings.signOut.confirm`, `connection.reconnecting`.

## Seed (scripts/dev/stack.sh reset)

carol has no household (onboarding flows; `launch "$U" carol`). alice owns "Mock Household" (`11111111-1111-4111-8111-111111111111`, invite `MOCK1234`): Trader Joe's
(Milk 1 gal, Bananas), Costco (Paper towels), Unsorted (Batteries), bought: Eggs. bob owns "The
Neighbors" (`JOIN5678`) and must join `MOCK1234` to see the list.

## Gotchas

- **Two booted simulators**: once a second simulator boots, `axe describe-ui` returns an empty tree
  for the other device (relaunching the app does not help; `sim.sh shutdown` + `sim.sh boot` of that
  device does). For cross-device checks drive the second device, assert via the API, and read the
  first device's `screen.png` (`snap.sh`). Each device keeps its own log (`.dev/logs/ios-app-<udid>.log`).

- **Rows must be default-style Buttons.** Inside a `List` cell, `.buttonStyle(.plain)`, `.bordered` and
  `.onTapGesture` never receive AXe/HID synthetic taps (the hit test resolves, the action never runs);
  the default button style goes through cell selection and works. Keep this rule in every list row.
- **Deep links** (`ios.sh open "$U" householdhelper://…` or `launch … <link>`) trigger SpringBoard's
  "Open in Household Helper?" prompt; the helper taps Open by coordinates. Never call `simctl openurl`
  directly or every later tap silently hits that sheet. `ios.sh confirm "$U"` clears a stray one.
- Full swipes on list items trigger the full-swipe action (Bought / Delete + undo toast); catalog rows
  only reveal a Delete button, so swipe then `ios.sh label "$U" Delete`.
- Context menus: `ios.sh longpress "$U" <id>` then `ios.sh label "$U" "Move to shop"` → `label … Costco`.
- Alerts ignore `accessibilityIdentifier` on their buttons; tap them by coordinates from the tree
  (filter `type == "Button"` by label; the alert's button is the narrower one). Use `.alert`, not
  `.confirmationDialog`, for confirmations: iOS 26 renders dialogs from Form rows as popovers.
- After a sign-out, a launch made with `HH_UITEST_USER` signs the same user straight back in. To
  look at the sign-in screen, `ios.sh launch "$U" none` first.
- Push: a banner for the household on screen is suppressed by design (the list already updated over
  SSE); push for another household the user is a member of (join `JOIN5678` as alice through the API
  before launching). A tap while the app runs switches household (log `opened household …`). With the
  app terminated, AXe taps never reach the home screen (not the banner, not even an app icon), so the
  cold-start tap path (`pendingHouseholdID`, applied once households load) is verified on a device.
- `ios.sh springboard "$U" "<label regex>"` taps any SpringBoard element (alert buttons) by label.
- The selected household persists across launches (UserDefaults); after joining another one, switch
  back in Settings (`settings.household.<name>`) before asserting on Mock Household data.

- `ios.sh build` output is filtered to `error:` lines; the full log is `.dev/logs/xcodebuild.log`.
- First build after an SPM change resolves Firebase (minutes). Keep `.dev/DerivedData`; never delete it casually (27 GB free).
- `axe type` needs a focused field: tap it first. If the keyboard hides a control, `ios.sh swipe "$U" up`.
- Segmented pickers expose segments by label, not by the picker's identifier.
- Unit tests: `scripts/dev/ios.sh unit` (golden decoding + grouping). UI tests: `ios.sh uitest SmokeTests` (step I2).
