# Household Helper

A shared household assistant. **Iteration 1** is a live shared shopping list; home budgeting
comes next on the same backend.

## Architecture

```
apps/ios      SwiftUI (iOS 26, Liquid Glass via system chrome)  ─┐
apps/android  Jetpack Compose (Material 3 Expressive)            ─┤── HTTPS/SSE ──▶  hh-api.fanslau.me
                                                                  │                  apps/api: Go, SQLite,
       Firebase Authentication (Google, Sign in with Apple)  ◀────┘                  Litestream → R2, FCM push
       issues the ID tokens; the API verifies them (JWKS)
```

- **`apps/api`** — Go 1.27, stdlib `net/http`, SQLite via `modernc.org/sqlite`, embedded
  migrations, Server-Sent Events per household, FCM HTTP v1 push sent straight from Go. Runs on the
  VPS as `app@hh-api` (port 8081 behind Caddy/Cloudflare, see the `vps` repo). The contract is
  [apps/api/API.md](apps/api/API.md) plus golden JSON fixtures that both clients decode in tests.
- **`apps/ios`** — XcodeGen project, Swift 6, `@Observable` stores, URLSession + hand-parsed SSE,
  Firebase Auth + Google Sign-In + Sign in with Apple, FirebaseMessaging. See [apps/ios/README.md](apps/ios/README.md).
- **`apps/android`** — AGP 9 with built-in Kotlin, Compose + material3 1.5 (Expressive), Navigation 3,
  Ktor (OkHttp, SSE), Firebase Auth + Credential Manager, FCM. See [apps/android/README.md](apps/android/README.md).

**The API is the security boundary.** Identity comes only from the verified Firebase token; every
household route checks membership (non-members get 404) and every row query is scoped by household.
Invite codes, `bought_at`, `sort_order` and push recipients are computed server-side.

Dropped from the Expo era: web target, Expo mock mode, email magic link (Google + Apple instead).

## Layout

```
apps/api/        Go API: cmd/hh-api, internal/{config,auth,store,devseed,sse,push,httpapi}, API.md, Makefile
apps/ios/        HouseholdHelper.xcodeproj (generated from project.yml), HouseholdHelper/, tests, Config/*.xcconfig
apps/android/    Gradle project, app/src/{main,dev,prod,test,androidTest}
scripts/dev/     the Claude/Adam dev toolkit (stack, tokens, simulator/emulator drivers, snapshots, asserts)
.claude/skills/  dev-stack, verify-realtime (+ apps/ios:verify, apps/android:verify inside the apps)
.github/         api-ci, deploy-api (VPS), android-ci
.githooks/       pre-commit → scripts/dev/secrets-check.sh
```

## Running locally

1. `scripts/dev/doctor.sh` — tool versions, simulators, AVDs, free disk, stack status.
2. `scripts/dev/stack.sh up` — Firebase Auth **emulator** (`127.0.0.1:9099`, UI `:4000`) plus the API on
   `127.0.0.1:8091` with `DEV_SEED=1`: users `alice@dev.local` / `bob@dev.local` (password `password`),
   households *Mock Household* (invite `MOCK1234`) and *The Neighbors* (`JOIN5678`), fixed UUIDs. `stack.sh reset` reseeds.
3. iOS: open `apps/ios/HouseholdHelper.xcodeproj`, scheme **HouseholdHelper**, iPhone 17 (iOS 26.3), Play →
   "Sign in as Alice". The Debug configuration bakes the emulator + `localhost:8091` into the bundle.
4. Android: run configuration `app`, flavor **dev**, AVD `Pixel_10_Pro` → "Sign in as Bob". The dev flavor
   reaches the host through `adb reverse` (`scripts/dev/android.sh avd up` sets it up) and ships a
   fabricated `google-services.json`.
5. API only: `scripts/dev/api.sh alice GET /v1/households`, `scripts/dev/sse.sh alice <hid> 30`.

No Docker, no Java for the emulator, no real Firebase project needed for day-to-day work. The
real-Firebase check before a release uses the **HouseholdHelper Firebase** scheme / the **prod**
flavor against the API in real-Firebase mode (`apps/api/.env.example`, commented block).

## Verification flow

Claude drives every UI change in the simulator (AXe) and the emulator (adb/uiautomator), asserting on
the accessibility tree, the API and the logs before a human checkpoint; the skills under
`.claude/skills` and `apps/*/.claude/skills` document the loop, the shared accessibility-identifier
vocabulary and the pitfalls. `scripts/dev/realtime.sh` runs the two-device realtime check
(iOS Alice ↔ Android Bob). The authoritative plan with the step list lives at
`~/dev/household-helper-plan.md` (outside the repo).

Before a PR: `make -C apps/api test`, `scripts/dev/ios.sh unit`, `scripts/dev/android.sh unit`; UI
tests `scripts/dev/ios.sh uitest SmokeTests` and `scripts/dev/android.sh uitest` need the local stack.

## Brand

The mark ("Orbit") is a roof that turns into a tick, with a spark orbiting the house. One 120 × 120
geometry drives everything: `apps/ios/HouseholdHelper/Support/BrandMark.swift` and
`apps/android/.../ui/BrandMark.kt` draw it in the apps (sign-in hero, loading indicator, the spark
as the "smart" glyph on suggestions); `scripts/dev/brandmark.swift <dir>` renders the iOS app-icon
PNGs (default, dark, tinted) into `Assets.xcassets/AppIcon.appiconset`; the Android adaptive icon is
the same paths as vector drawables (`res/drawable/ic_launcher_*.xml`, `ic_notification.xml`).
Colours: Leaf `#17A06A`, Deep `#0E6B47`, Mint `#6FD9A6`, Ink `#10201A` (`Brand.swift` / `Brand.kt`).
The design canvas (palette, icon set, logo exploration, screen mockups) lives in Claude Design.

## Deploying

- **API**: `.github/workflows/deploy-api.yml` (copy of `vps/workflows/deploy-go-app.yml`) runs on pushes
  to `main` touching `apps/api/**`: builds a static binary, ships it with `deploy-shell`, health-polls
  and rolls back on failure. Repo vars `APP_NAME=hh-api APP_DOMAIN=hh-api.fanslau.me MAIN_PKG=./cmd/hh-api
  WORKING_DIR=apps/api`, secrets `VPS_HOST VPS_SSH_KEY VPS_KNOWN_HOSTS`, environment `production`.
  Server config lives in `/etc/hh-api/env` on the VPS (`FIREBASE_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE`).
- **iOS**: Xcode Cloud (PR builds + TestFlight on `main`); `apps/ios/ci_scripts/ci_post_clone.sh` writes
  `GoogleService-Info.plist` from a secret.
- **Android**: `android-ci.yml` builds the dev flavor and unit tests; Play Console upload is manual for now.

## Console setup (one-time, outside the repo)

Apple Developer App ID `com.householdhelper.app` (Sign in with Apple, Push Notifications, APNs key),
a Firebase project (Google + Apple providers, iOS and Android apps, APNs key under Cloud Messaging),
a GCP service account `hh-api-fcm` with only `roles/firebasemessaging.admin` whose key sits at
`/etc/hh-api/fcm-sa.json` on the VPS. Details per platform in the app READMEs. None of these files
are ever committed — see the "No secrets in git" section of [CLAUDE.md](CLAUDE.md).

## Roadmap → budgeting

Budgeting lands as new SQLite migrations and `/v1` routes on the same API, with the same
membership scoping; reporting as Go queries; recurring work as in-process schedulers (the API is a
single process). External integrations (bank import) get their secrets from `/etc/hh-api/env`.
