# CLAUDE.md

Guidance for working in this repo. Read alongside [README.md](README.md) (architecture) and
[CONTRIBUTING.md](CONTRIBUTING.md) (commit conventions). The migration plan with the step list
and checkpoint protocol lives at `~/dev/household-helper-plan.md` (outside the repo).

## No secrets in git — ever (enforced)

This rule outlives the migration and overrides convenience. A secret that reaches a commit is
compromised even after removal from history: rotate it, don't just delete it.

- **Never stage or commit**: `.env` files (only `*.example`), `GoogleService-Info.plist`, real
  `google-services.json` (only the fabricated `apps/android/app/src/dev/google-services.json` is
  tracked), `*.p8 *.p12 *.jks *.keystore *.pem *.key`, `fcm-sa*.json`, SSH keys, `*.db*`, anything
  under `.dev/`, and no private keys, service-account JSON, JWTs, API keys, OAuth client secrets,
  `sb_secret_*`, GitHub/Slack/AWS tokens or `KEY=value` lines with real values inside any file —
  including docs, tests, fixtures, logs, screenshots and commit messages.
- **Enforcement**: `scripts/dev/secrets-check.sh` scans staged files. It runs automatically as a
  Claude Code `PreToolUse` hook before any `git commit` (see `.claude/settings.json`; a finding
  blocks the commit) and as the git pre-commit hook (`git config core.hooksPath .githooks`, run
  once per clone). Run `scripts/dev/secrets-check.sh --all` to audit the whole tree.
- **If it fires**: remove the value, put it in the right secret store (`/etc/hh-api/env` on the
  VPS, GitHub/Xcode Cloud secrets, local gitignored `.env`), reference it by env var, and re-run.
  Only append `secrets-check: allow` to a line that is a documented non-secret (e.g. a public
  publishable key or a fabricated demo value); never to silence a real one. Do not bypass the
  hooks (`--no-verify`) for any reason.
- **Dev fakes must look fake**: `demo-api-key`, `password`, `MOCK1234`, fabricated Firebase app
  ids. Never copy a real value "just for local testing", and never shape a fake like a real
  credential (`AIza…`, `ghp_…`, `AKIA…`, PEM blocks): GitHub secret scanning alerts on the shape
  alone, and `secrets-check.sh` refuses those even with an allow comment. When an SDK validates
  the shape (Firebase Installations wants 39 chars starting with `A`), satisfy only what it checks.
- **Logs and output**: never print tokens, sessions, keys or full `Authorization` headers; the
  dev scripts write tokens only to stdout when explicitly asked (`token.sh`), never to `.dev/logs`.

## What this is

Household Helper — a shared shopping list (budgeting next) with **three codebases**: the Go API
`apps/api` (SQLite, SSE, FCM push) running on the VPS as `hh-api`, and native clients `apps/ios`
(SwiftUI) and `apps/android` (Compose). Firebase Authentication is the identity provider; the API
verifies its ID tokens. There is no Supabase, no web client and no Expo any more.

## The API is the security boundary (read before touching data access)

The clients are untrusted. Everything that decides who sees what lives in `apps/api`:

- **Identity only from the verified token.** `requireAuth` verifies the bearer token (Firebase JWKS,
  or the emulator verifier in dev) and sets the Principal; `added_by` / `created_by` are never read
  from the request body.
- **Membership on every household route.** `/v1/households/{hid}/…` goes through `member()`; a
  non-member gets **404** (never 403 — do not leak existence). Every row query is additionally
  scoped by `household_id` (catalog via its shop). Membership changes only through
  `POST /v1/households` and `POST /v1/households/join` (rate-limited per uid).
- **Server-computed facts**: invite codes (`internal/ids`), `bought_at`, `sort_order`, the
  `quantity` copied from a catalog `default_unit`, push recipients (members minus the actor).
- **Dev-only features are triple-gated.** The `alg=none` emulator verifier and `DEV_SEED` are
  refused on `PORT=8081` or a non-loopback `HOST` (`internal/config`); they never appear in the VPS
  env example. Never add a bearer bypass.
- **Publish after commit.** SSE events and push notifications fan out only after the database
  transaction committed (`publishTo` in `httpapi/events.go`).
- **Push is best-effort** and sends only list-item inserts and joins, never to the actor; dead
  tokens are deleted on FCM's say-so, stale ones pruned daily.
- Schema changes are **new migration files only** (`internal/store/migrations/NNNN_*.sql`, applied
  by `store.Migrate`); never edit an applied one.
- The contract is `apps/api/API.md` + `testdata/golden/*.json`. A JSON tag change means: update
  `API.md`, `make golden`, fix `ModelsDecodingTests` (iOS) and `ModelsDecodingTest` (Android).

## Project standards

- **Go** (`apps/api`): stdlib `net/http`, `log/slog` JSON logs (uid yes, token never), writer pool of
  one + reader pool of four, tiny write transactions, `go test -race ./...` green; mirror the
  existing handler/store/test shapes (`newEnv`, `fakeVerifier`). `make -C apps/api test` before a commit.
- **iOS** (`apps/ios`): SwiftUI only, Swift 6 strict concurrency with MainActor default isolation
  (`nonisolated` models/services), `@Observable` stores injected via `.environment`, URLSession +
  Codable, config **baked** into the build configuration via `Config/*.xcconfig` → Info.plist (never
  scheme env vars; `HH_UITEST_USER` is the one runtime input), system chrome for Liquid Glass (no
  custom bar backgrounds, no `glassEffect` on content), every control carries an identifier from
  `Support/A11y.swift`, list rows are default-style `Button`s (synthetic taps reach nothing else),
  confirmations use `.alert`. Edit `project.yml`, then `scripts/dev/ios.sh gen` (the `.xcodeproj` is committed).
- **Android** (`apps/android`): Compose + material3 1.5 (Expressive; keep the Expressive surface
  small), Navigation 3, manual DI via `AppContainer`, Ktor, `kotlinx.serialization` (snake_case),
  flavors `dev` (emulator, `adb reverse`, fabricated `google-services.json`, FCM off) and `prod`.
  Test tags from the same vocabulary as iOS, exposed with `testTagsAsResourceId` on the root and
  `Modifier.exposeTestTags()` on every sheet/dialog/popup.
- **Verification rule**: every UI change is driven and asserted in the simulator/emulator with the
  verify skills (`apps/ios:verify`, `apps/android:verify`, root `dev-stack`, `verify-realtime`)
  before it is offered at a checkpoint; assert on the tree/API/log, read screenshots for layout only.
- **Dev loop**: `scripts/dev/stack.sh up` (Auth emulator + seeded API), `scripts/dev/doctor.sh` when
  something looks off. Never `xcrun simctl … booted` (use UDIDs from `scripts/dev/lib.sh`).
- **Commits**: Conventional Commits (scopes in CONTRIBUTING.md). Work on `migration/native`; `main`
  deploys the API.

## Secrets & environment handling

- Server config lives in `/etc/hh-api/env` on the VPS (`FIREBASE_PROJECT_ID`,
  `FCM_SERVICE_ACCOUNT_FILE` → `/etc/hh-api/fcm-sa.json`, 0640 root:hh-api) and in GitHub /
  Xcode Cloud secrets for CI. Locally, `apps/api/.env` (git-ignored, from `.env.example`).
- Client-side values that are **public by design** (Firebase project id, publishable API keys,
  OAuth client ids) still stay out of git for the real project: `GoogleService-Info.plist`,
  `apps/android/app/src/prod/google-services.json`, `apps/ios/Config/Secrets.xcconfig` and the Gradle
  property `hh.googleWebClientId` are injected locally or by CI.
- Tokens: Firebase keeps sessions (keychain / its own storage); the apps never persist ID tokens
  themselves and never log them. The API logs the uid, never the `Authorization` header.
- Rotating a leaked key: rotate in the Firebase/Google Cloud/Apple console, update the secret
  store, redeploy. A committed secret is compromised even after removal from history.
- New external integration: placeholder in the matching `.env.example`, a line in the README, real
  value through the secret store.
