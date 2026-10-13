---
name: dev-stack
description: Start, stop, reset and talk to the local hh-api + Firebase Auth emulator stack as the seeded users alice/bob (tokens, curl, logs).
---

# Local stack (API + Auth emulator)

```bash
scripts/dev/stack.sh up        # emulator :9099 (UI :4000) + API :8091, seeded; idempotent
scripts/dev/stack.sh status    # api=ok (emulator <sha>) auth=ok seed=ok
scripts/dev/stack.sh reset     # fresh db + seed (deletes apps/api/hh-dev.db*)
scripts/dev/stack.sh down
scripts/dev/stack.sh logs api 50          # or: logs firebase
```

Logs: `.dev/logs/api.log` (JSON, one line per request, uid but never the token), `.dev/logs/firebase.log`.
The API binary is built to `.dev/bin/hh-api`; `up` rebuilds it, so after a code change run `up` again.

## Seeded data (internal/devseed, fixed ids)

| What | Value |
|---|---|
| Users | `alice@dev.local` (uid `dev-alice`), `bob@dev.local` (`dev-bob`), password `password` |
| Mock Household | `11111111-1111-4111-8111-111111111111`, owner alice, invite `MOCK1234` |
| The Neighbors | `22222222-2222-4222-8222-222222222222`, owner bob, invite `JOIN5678` (alice not a member) |
| Shops (Mock) | Trader Joe's `33333333-3333-4333-8333-000000000001`, Costco `…0002`, Pharmacy `…0003` |
| List (Mock) | Milk `1 gal` (TJ), Bananas (TJ), Paper towels (Costco), Batteries (Unsorted), Eggs (bought) |

The emulator forgets users on restart; the API seed and `token.sh` both re-create them.

## Call the API

```bash
scripts/dev/token.sh alice                                   # ID token on stdout
scripts/dev/api.sh alice GET /v1/me
scripts/dev/api.sh alice GET /v1/households
scripts/dev/api.sh bob   POST /v1/households/join '{"code":"MOCK1234"}'
scripts/dev/api.sh alice POST /v1/households '{"name":"Test Home"}'
scripts/dev/api.sh alice GET /v1/households/<hid>/invites
```

Expect `HTTP <code>` then a compact JSON body; errors use `{"error":{"code","message","fields"}}`.

## Gotchas

- Dev-only features are refused on `PORT=8081` or a non-loopback `HOST`; never put the emulator host in the VPS env.
- `stack.sh up` after a Go change rebuilds; `go test -race ./...` in `apps/api` is the fast check (`make -C apps/api test`).
- Don't pipe `stack.sh up` into `head`; it prints one status line when ready.
