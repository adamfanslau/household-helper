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

Assert from the tree, the API (`assert.sh api alice /v1/… '<jq>'`) and the log before reading
`screen.png`; read the PNG for layout questions only. `launch "$U" none` relaunches like a tap on
the home screen (keeps the Firebase session and the selected household) — test it after any
config change. Light/dark and text size: `ios.sh appearance "$U" dark`, `ios.sh textsize "$U" ax5`.

## Identifiers (Support/A11y.swift; same vocabulary as Android testTags)

`signin.dev.alice|bob`, `onboarding.mode` (segmented: tap by label "Create"/"Join"), `onboarding.input`,
`onboarding.submit`, tabs by label (`ios.sh label "$U" List|Shops|Settings`), `list.item.<name>`, `list.bought.toggle`,
`settings.household.<name>`, `settings.signOut`; later: `list.input`, `list.add`, `shops.*`, `shop.*`,
`settings.inviteCode`, `settings.share`.

## Seed (scripts/dev/stack.sh reset)

carol has no household (onboarding flows; `launch "$U" carol`). alice owns "Mock Household" (`11111111-1111-4111-8111-111111111111`, invite `MOCK1234`): Trader Joe's
(Milk 1 gal, Bananas), Costco (Paper towels), Unsorted (Batteries), bought: Eggs. bob owns "The
Neighbors" (`JOIN5678`) and must join `MOCK1234` to see the list.

## Gotchas

- `ios.sh build` output is filtered to `error:` lines; the full log is `.dev/logs/xcodebuild.log`.
- First build after an SPM change resolves Firebase (minutes). Keep `.dev/DerivedData`; never delete it casually (27 GB free).
- `axe type` needs a focused field: tap it first. If the keyboard hides a control, `ios.sh swipe "$U" up`.
- Segmented pickers expose segments by label, not by the picker's identifier.
- Unit tests: `scripts/dev/ios.sh unit` (golden decoding + grouping). UI tests: `ios.sh uitest SmokeTests` (step I2).
