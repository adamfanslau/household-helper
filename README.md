# Household Helper

A shared household assistant app. **Iteration 1** is a live shared shopping list;
the roadmap is a full home-budgeting app.

## Architecture (iteration 1)

```
Expo / React Native app (apps/mobile)
  ├── Supabase Auth        — Google OAuth + email magic link
  ├── Supabase Postgres    — direct CRUD via @supabase/supabase-js, secured by RLS
  └── Supabase Realtime    — live shopping-list / shop / catalog updates
```

There is **no custom backend** — the mobile app talks directly to Supabase and
Row-Level Security is the data boundary. Future server-side needs are met
Postgres-first (views, RPCs, `pg_cron`); Supabase Edge Functions
(`supabase/functions/`) are reserved for work that needs secrets or third-party
API calls.

## Layout

```
apps/mobile/        Expo app (Expo Router, TypeScript)
supabase/
  migrations/       0001 schema · 0002 RLS + grants + functions · 0003 realtime
  tests/            rls_smoke_test.sql — RLS / sharing / invite assertions
  config.toml       auth providers + redirect URLs
```

## Data model

`households` ← `household_members` (user join) · `household_invites` (join codes)
`shops` → `catalog_items` (reusable items per shop)
`shopping_list_items` (the live "need to buy" list; can reference a catalog item or be free-form)

All domain tables have RLS scoping every row to households the caller belongs to.
Membership changes go through SECURITY DEFINER functions `create_household(name)` and
`join_household(code)`.

## Running locally

### 1. Backend (Supabase)

Requires Docker running and the Supabase CLI (or use `npx supabase`).

```bash
npx supabase start          # boots Postgres + Auth + Realtime, applies migrations
npx supabase db reset       # re-apply migrations from scratch
npx supabase status         # prints the API URL + publishable (anon) key
```

Verify the security model:

```bash
CID=$(docker ps --filter name=supabase_db --format '{{.Names}}' | head -1)
docker cp supabase/tests/rls_smoke_test.sql "$CID":/tmp/t.sql
docker exec -i "$CID" psql postgresql://postgres:postgres@127.0.0.1:5432/postgres -f /tmp/t.sql
```

### 2. Mobile app

```bash
cd apps/mobile
cp .env.example .env        # fill EXPO_PUBLIC_SUPABASE_URL / _ANON_KEY from `supabase status`
npm install --legacy-peer-deps
npx expo start              # press i (iOS sim), a (Android emulator), or scan in Expo Go
```

Notes:
- iOS simulator / web reach `http://127.0.0.1:54321`. **Android emulator** uses
  `http://10.0.2.2:54321`; a **physical device** needs your machine's LAN IP.
- **Magic link** works locally — the email is captured by Mailpit at
  http://127.0.0.1:54324.
- **Google sign-in** needs real OAuth credentials: set
  `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` / `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET`
  in your shell before `supabase start` (see `supabase/config.toml`).

### Mock mode (no backend)

For UI work in the emulators without Supabase or Docker running at all:

```bash
cd apps/mobile
npm run ios:mock            # or: npm run android:mock
```

This swaps the Supabase client for an in-memory fake (`lib/mock/`) — you boot
pre-signed-in as `dev@mock.local` with a seeded household, shops, catalog, and
shopping list. Realtime-style updates work within the app; data resets on a full
reload. Seeded invite codes: `MOCK1234` (your household), `JOIN5678` (a second
household, for testing the join flow). Mock mode is dev-only (`__DEV__`-gated)
and stripped from release builds. The scripts pass `--clear` because Metro
caches inlined `EXPO_PUBLIC_*` values — start once with `--clear` when switching
back to real mode too (`npx expo start --ios --clear`).

## Regenerating DB types

```bash
cd apps/mobile
npx supabase gen types typescript --local > types/database.ts
```

## Roadmap → budgeting

- Add a budgeting schema (accounts, transactions, categories, budgets) as migrations with
  RLS, using the same `is_household_member(hid)` pattern.
- Aggregation/reporting as SQL views + RPCs; recurring transactions via `pg_cron`.
- Introduce Supabase Edge Functions only when a feature needs secrets or external APIs
  (e.g. bank import, notifications).
