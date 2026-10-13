# scripts/dev — the Claude/Adam dev toolkit

Each script does one whole step and prints one compact result. Long-running things write
logs to `.dev/logs/` and pid files to `.dev/pids/`; screenshots and trees go to `.dev/shots/`.
`.dev/` is gitignored. All scripts source `lib.sh` (constants, UDIDs, helpers).

| Script | Purpose | Added in step |
|---|---|---|
| `doctor.sh` | tool versions, iOS 26.3 simulators (UDIDs), AVDs, free disk, is the local stack up | 0 |
| `sim.sh` | `list` / `resolve "<name>" [runtime]` / `boot <udid>` / `shutdown <udid>` / `state <udid>` — never `booted` | 0 |
| `disk.sh` | free disk + the caches that grow (DerivedData, Gradle, shots) | 0 |
| `secrets-check.sh` | refuse secrets in staged files (`--all` for the tree, `--hook` = Claude PreToolUse mode); wired as git pre-commit via `.githooks/` | 0 |
| `stack.sh`, `token.sh`, `api.sh`, `sse.sh` | local API + Auth emulator, ID tokens, curl as alice/bob | 2–5 |
| `ios.sh`, `snap.sh`, `assert.sh` | build/install/launch/drive/snapshot/assert on a simulator (`open` confirms the deep-link prompt) | 7–8 |
| `android.sh` | the same on `Pixel_10_Pro` | 12 |
| `realtime.sh`, `handoff.sh` | cross-device check; checkpoint hand-off message | 13 / 7 |

## Fixed facts (2026-10-13)

- iPhone 17 (iOS 26.3): `89850DF1-19BE-4DAF-92D5-B6411AF061A4` · iPhone 16e (iOS 26.3): `D1A7B231-8689-40A0-8536-126AC063188E`
  (an iPhone 16e also exists on iOS 18.3 — always resolve by UDID).
- Android: AVD `Pixel_10_Pro` (API 37.2, Play image → no `adb root`), usually `emulator-5554`.
- Local API `http://127.0.0.1:8091`, Auth emulator `127.0.0.1:9099` (UI :4000), project `demo-household-helper`.
  From the Android emulator use `10.0.2.2` instead of `127.0.0.1`.

## AXe 1.8.0 (iOS driving) — flags confirmed on install

```
axe describe-ui --udid U [--point x,y]        # JSON accessibility tree: AXUniqueId (= accessibilityIdentifier), AXLabel, AXValue, type, frame
axe tap --id <identifier> --udid U            # or --label / --value, optional --element-type Button|TextField|…
axe tap -x <x> -y <y> --udid U
axe type "text" --udid U                      # US keyboard chars only; focus the field first (tap)
axe swipe --start-x X --start-y Y --end-x X --end-y Y [--duration s] --udid U
axe button home|lock|… --udid U
axe screenshot --output file.png --udid U     # or: xcrun simctl io U screenshot file.png
axe batch …                                   # several steps in one HID session (faster)
```

## Firebase Auth emulator

`npm run emulators` (pinned `firebase-tools` in the root `package.json`). Pure JS, no Java needed.
Admin endpoint for fixed-uid users (used by the Go dev seed):
`POST http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-household-helper/accounts`
with `Authorization: Bearer owner` and `{"localId","email","password","displayName"}`.
The emulator forgets users on restart — the seed re-creates them every start.
