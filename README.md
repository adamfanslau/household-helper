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

There is **no custom backend yet** — the mobile app talks directly to Supabase and
Row-Level Security is the data boundary. A Go API (`apps/api`, placeholder) will be
added for the budgeting iteration, where it owns heavier business logic.

## Layout

```
apps/mobile/        Expo app (Expo Router, TypeScript)
apps/api/           Go API — added later (budgeting)
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

## Regenerating DB types

```bash
cd apps/mobile
npx supabase gen types typescript --local > types/database.ts
```

## Roadmap → budgeting

- Stand up `apps/api` (Go) behind the same Supabase JWT (verify via JWKS).
- Add a budgeting schema (accounts, transactions, categories, budgets); the Go API owns
  aggregation/reporting, while the mobile app keeps using Supabase for auth + shopping list.
