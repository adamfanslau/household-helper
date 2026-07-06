# CLAUDE.md

Guidance for working in this repo. Read alongside [README.md](README.md) (architecture)
and [CONTRIBUTING.md](CONTRIBUTING.md) (commit conventions).

## What this is

Household Helper — Expo/React Native app on a **Supabase-only** backend (Postgres + Auth +
Realtime). Iteration 1 is a shared shopping list; budgeting comes later and stays
Supabase-first. The mobile app talks **directly** to Supabase; there is no server of our
own in the request path, and none is planned by default — server-shaped work goes
Postgres-first (views, RPCs, `pg_cron`), with Supabase Edge Functions reserved for
features that need secrets or external API calls. The database is the security
boundary — treat it as such.

## Project standards

- **Language/stack**: TypeScript (strict) in `apps/mobile`, SQL migrations in `supabase/`;
  any future server code is Deno/TypeScript Edge Functions in `supabase/functions/`. Match
  the surrounding style; keep comments sparse and about *why*.
- **Routing**: Expo Router (file-based) under `apps/mobile/app`. Auth/household gating lives
  in the layout files (`app/index.tsx`, `app/(app)/_layout.tsx`).
- **Data access**: go through the typed Supabase client in [lib/supabase.ts](apps/mobile/lib/supabase.ts).
  Keep DB row types in [types/database.ts](apps/mobile/types/database.ts) in sync with migrations
  (`npx supabase gen types typescript --local > types/database.ts` after schema changes).
- **Schema changes are migrations only.** Add a new `supabase/migrations/NNNN_*.sql`; never
  edit an already-applied migration. Verify with `npx supabase db reset`.
- **Commits**: Conventional Commits 1.0.0 (see CONTRIBUTING.md).
- **Before a PR**: `cd apps/mobile && npx tsc --noEmit`, then `npx supabase db reset` and the
  RLS smoke test in [supabase/tests/rls_smoke_test.sql](supabase/tests/rls_smoke_test.sql).

## Cybersecurity model (read before touching data access)

**Row-Level Security is the boundary, not the client.** The anon/publishable key ships in the
app and is assumed public — never rely on client code to enforce who-can-see-what.

- **RLS on by default.** Every table in `public` has RLS enabled. Any new table MUST enable RLS
  and add explicit policies in the same migration, scoped via `public.is_household_member(hid)`.
  A table without policies denies all access — that's the safe default; don't "fix" it by
  disabling RLS.
- **Membership mutations are funneled.** There is intentionally **no** direct `INSERT` policy on
  `household_members`. Joining/creating goes through the `SECURITY DEFINER` functions
  `create_household()` / `join_household()` ([0002_rls.sql](supabase/migrations/0002_rls.sql)).
  This also avoids RLS recursion (the helper is `SECURITY DEFINER` so it reads the table without
  re-triggering its own policy).
- **`SECURITY DEFINER` hygiene.** Any definer function MUST `set search_path = public`, validate
  `auth.uid()` is non-null, and be granted only to `authenticated` (revoke from `public`). Keep
  them minimal — they run with elevated rights.
- **Least privilege.** Table grants go to the `authenticated` role only. Never grant to `anon`
  for household data. The `service_role`/secret key is server-only — it bypasses RLS and MUST
  NOT appear in the mobile app or any `EXPO_PUBLIC_*` var.
- **Validate at the boundary.** Input constraints live in the schema (`check` constraints, FKs,
  enums-as-check). Client-side checks are UX only, never security.
- **Realtime respects RLS** — subscriptions only deliver rows the user may read. Don't broaden a
  publication assuming the client will filter.
- **Future Edge Functions** must derive the caller from the request's Supabase JWT (via the
  auth context / `getUser`), never from a client-supplied user/household id, and re-check
  authorization server-side — or query as the user so RLS applies. The `service_role` key
  lives only in function secrets, never the client; a function using it bypasses RLS and
  MUST do its own authorization checks.

## Secrets & environment handling

- **Public by design**: `EXPO_PUBLIC_*` vars are **inlined into the app bundle** at build time.
  Only put values there that are safe to ship: the Supabase URL and the publishable/anon key.
  Nothing else. If a value must stay secret, it cannot be an `EXPO_PUBLIC_*` var.
- **Never commit real secrets.** `.env` files are git-ignored (root + `apps/mobile`). Only
  `*.example` files are tracked. `apps/mobile/.env` currently holds the **local-dev** publishable
  key (a shared Supabase default, not sensitive); production keys must never be committed.
- **OAuth provider secrets** (e.g. Google) are referenced via env substitution in
  [supabase/config.toml](supabase/config.toml) — `env(SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET)` — and
  set in the shell/CI, never inline in the file.
- **Server/admin keys** (`service_role` / `sb_secret_*`, Postgres connection strings) belong only
  in backend/CI secret stores. They must never reach the mobile app, logs, or the repo.
- **No secrets in logs or errors.** Don't `console.log` tokens, sessions, or keys. Sessions are
  persisted via AsyncStorage by the Supabase client — don't hand-roll token storage.
- **Rotating a leaked key**: rotate it in the Supabase dashboard, update the relevant `.env`/CI
  secret, and (for OAuth) the provider console. A committed secret is compromised even after
  removal from history — rotate, don't just delete.
- When adding a new external integration, add a placeholder to the matching `.env.example`,
  document it in the README, and wire the real value through env vars / CI secrets.
