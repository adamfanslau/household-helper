# apps/ios — Household Helper for iOS

SwiftUI, iOS 26, Swift 6. The project file is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`scripts/dev/ios.sh gen`); the generated
`HouseholdHelper.xcodeproj` is committed so Xcode and Xcode Cloud open it directly.

## Schemes and configurations

| Scheme | Config | Auth | API | Needs |
|---|---|---|---|---|
| **HouseholdHelper** | Debug | Firebase Auth **emulator** (dev buttons Alice/Bob/Carol, `HH_UITEST_USER`) | `http://localhost:8091` | `scripts/dev/stack.sh up` |
| **HouseholdHelper Firebase** | DebugFirebase | real Firebase project (Google, Apple) | `http://localhost:8091` | files below + the API in real-Firebase mode |
| Archive of either | Release | real Firebase project | `https://hh-api.fanslau.me` | files below |

Values are baked into Info.plist by `Config/*.xcconfig`, so a relaunch from the home screen behaves
exactly like a launch from Xcode.

## Files that are not in git (real Firebase project only)

1. `HouseholdHelper/GoogleService-Info.plist` — from the Firebase console (iOS app `com.householdhelper.app`).
2. `Config/Secrets.xcconfig` — copy `Config/Secrets.xcconfig.example` and set `HH_GOOGLE_REVERSED_CLIENT_ID`
   (the `REVERSED_CLIENT_ID` from the plist) and `HH_TEAM_ID` (Apple Developer team). Not secrets,
   but per project; the secrets scanner refuses to commit either file.

On Xcode Cloud both are written by `ci_scripts/ci_post_clone.sh` from the workflow environment
variables `GOOGLE_SERVICE_INFO_PLIST_B64` (secret) and `HH_TEAM_ID`.

## Console setup (once)

- Apple Developer: App ID `com.householdhelper.app` with **Sign in with Apple** (and Push for step 11);
  Xcode-managed signing with your team.
- Firebase: Authentication providers **Google** and **Apple**; register the iOS app and download the
  plist. Google Sign-In needs no extra OAuth client; Firebase creates it (`CLIENT_ID` / `REVERSED_CLIENT_ID`).
- Apple provider in Firebase needs the Services ID / key only for web; for native iOS the bundle id is enough.

## Verify

`apps/ios/.claude/skills/verify/SKILL.md` documents the simulator loop (`scripts/dev/ios.sh`),
`scripts/dev/ios.sh unit` runs the unit tests (golden fixture decoding, grouping, SSE parser),
`scripts/dev/ios.sh uitest SmokeTests` the XCUITest smoke on a fresh seed.
