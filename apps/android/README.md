# apps/android — Household Helper for Android

Kotlin + Jetpack Compose (Material 3 Expressive), minSdk 28, compileSdk 37, Navigation 3, Ktor,
Firebase Auth. The Gradle project was written by hand to the Android Studio "Empty Activity (Compose)"
shape; open `apps/android` in Android Studio as usual.

| Flavor | Auth | API | Firebase config |
|---|---|---|---|
| `dev` (`com.householdhelper.app.dev`) | Auth **emulator** at `127.0.0.1:9099` via `adb reverse`, dev sign-in buttons, `HH_UITEST_USER` extra | `http://127.0.0.1:8091` via `adb reverse` | `app/src/dev/google-services.json` (fabricated, committed) |
| `prod` | real project (Google via Credential Manager) | `https://hh-api.fanslau.me` | `app/src/prod/google-services.json` (git-ignored) |

Pins live in `gradle/libs.versions.toml` (checked 2026-10-13): AGP 9.4.1 with built-in Kotlin, Kotlin
2.4.21, Compose BOM 2026.09.00 with **material3 1.5.0-beta01** (Material 3 Expressive is on the 1.5
line), Navigation 3 1.2.0, Firebase BoM 35, Ktor 3.6, kotlinx.serialization 1.11.

`./gradlew :app:installDevDebug` installs on the running AVD; `scripts/dev/android.sh` wraps the
loop; `apps/android/.claude/skills/verify/SKILL.md` documents driving it. Unit tests
(`:app:testDevDebugUnitTest`) decode the API golden fixtures like the iOS tests do and cover list
grouping and SSE change application; `:app:connectedDevDebugAndroidTest` runs a Compose smoke test
against the local stack (`scripts/dev/android.sh uitest` after `stack.sh reset`).

Interaction model (see the plan's §3.0): tap a row = bought / un-buy, swipe right = bought, swipe left
= delete with a 5 s Undo snackbar, long-press = sheet with Move to shop / Edit / Mark bought / Delete.
The add bar sits above the keyboard. Realtime arrives over SSE (`data/EventsClient.kt`, reconnects
with backoff and refetches on foreground); a "Reconnecting…" pill shows after 3 s offline. Deep links:
`householdhelper://list | shops | shops/<id> | settings | join/<CODE>`.
