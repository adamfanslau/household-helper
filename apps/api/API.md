# hh-api — HTTP contract

Base URL: `https://hh-api.fanslau.me` (prod), `http://localhost:8091` (dev; `10.0.2.2:8091` from the
Android emulator). All `/v1` routes need `Authorization: Bearer <Firebase ID token>`. JSON only,
`snake_case`, timestamps are RFC 3339 UTC with milliseconds (`2026-01-01T10:00:00.000Z`), ids are
UUID strings (clients may mint their own UUID for `POST …/items` to make retries idempotent).

Kept in sync by hand with the handlers. The wire shapes are pinned by
`internal/httpapi/testdata/golden/*.json` (`make golden` after a deliberate change) and decoded by
the iOS and Android unit tests; a tag change touches all three.

## Authentication

Identity comes only from the verified token (`sub` → user id, `email`, `name`,
`firebase.sign_in_provider`). The user row is upserted on first sight (throttled). Clients never
send a user id; `added_by` / `created_by` in bodies are ignored.

| Mode | When | Tokens |
|---|---|---|
| `firebase` | `FIREBASE_PROJECT_ID` set, no emulator host | RS256, keys from Google's JWKS |
| `emulator` | `FIREBASE_AUTH_EMULATOR_HOST` set (loopback + non-8081 only) | unsigned emulator tokens, same iss/aud/exp checks |

`GET /healthz` → `{"version":"<sha>","auth":"firebase|emulator"}` (503 + `"db":"not ready"` when the db fails). `GET /readyz` → `ok`.

## Errors

```json
{"error":{"code":"not_found","message":"no such household","fields":null}}
```

| HTTP | code | meaning |
|---|---|---|
| 400 | `invalid_request` | malformed JSON, failed validation (`fields` maps field → hint), or a shop/catalog reference outside the household |
| 401 | `unauthorized` | missing, invalid or expired token |
| 404 | `not_found` | unknown route, or the caller is not a member of the household (non-members cannot tell whether it exists) |
| 409 | `conflict` | state does not allow the action |
| 413 | `payload_too_large` | body over 64 KiB |
| 429 | `rate_limited` | too many join attempts (10 per minute per user) |
| 500 | `internal` | logged with the `X-Request-Id` echoed on every response |

Every response carries `X-Request-Id` (a client-supplied one ≤ 64 chars is echoed). `/v1` responses are `Cache-Control: no-store`.

## Resources

**User** (`GET /v1/me`): `id`, `email`, `display_name`, `provider`, `created_at`, `last_seen_at`.

**Household**: `id`, `name`, `created_by` (nullable), `created_at`, `updated_at`, `role` (`owner`|`member`, the caller's membership; present on household responses).

**Invite**: `id`, `household_id`, `code` (8 chars, A–Z/0–9), `created_by`, `created_at`, `expires_at` (nullable), `revoked_at` (nullable).

**Shop**: `id`, `household_id`, `name`, `sort_order` (int, server-assigned on create), `created_at`, `updated_at`, `needed_count` (int, computed: list items in this shop not yet bought, i.e. `needed` + `in_basket`).

**CatalogItem** (a household's *product*, not tied to a shop): `id`, `household_id`, `name` (unique per household, case-insensitive), `shop_id` (nullable: the shop it was last added for), `default_unit` (nullable: the quantity last used), `created_at`, `updated_at`. Adding a list item by name creates or updates the product of that name, so the catalog is the source of typing hints.

**ShoppingListItem**: `id`, `household_id`, `name`, `shop_id` (nullable → "Unsorted"), `catalog_item_id` (nullable), `quantity` (nullable), `status` (`needed` | `in_basket` | `bought`), `added_by` (nullable), `created_at`, `updated_at`, `bought_at` (nullable; set by the server exactly when `status` is `bought`). Shopping is two steps: tapping an item in the shop makes it `in_basket` (still on the list, ticked, shown last in its shop); checkout turns the basket into `bought`.

## Routes

Household-scoped routes (`…/households/{hid}/…`) require membership; otherwise 404.

| Method & path | Body | Returns |
|---|---|---|
| `GET /v1/me` | | User |
| `GET /v1/households` | | `[Household]`, oldest first |
| `POST /v1/households` | `{"name"}` (1–100) | 201 Household (caller is `owner`; the first invite is minted too) |
| `POST /v1/households/join` | `{"code"}` (case-insensitive, trimmed) | 200 Household (`role: member`; idempotent) · 404 invalid/expired/revoked · 429 |
| `GET /v1/households/{hid}` | | Household |
| `PATCH /v1/households/{hid}` | `{"name"}` | Household |
| `GET /v1/households/{hid}/invites` | | `[Invite]`, newest first (show the newest with `revoked_at == null`) |
| `POST /v1/households/{hid}/invites` | | 201 Invite |
| `POST /v1/households/{hid}/invites/{id}/revoke` | | Invite |
| `GET /v1/households/{hid}/shops` | | `[Shop]` by `sort_order` |
| `POST /v1/households/{hid}/shops` | `{"name"}` (1–100) | 201 Shop (`sort_order` = max+1) |
| `GET /v1/households/{hid}/shops/{shopId}` | | Shop |
| `PATCH /v1/households/{hid}/shops/{shopId}` | `{"name"?, "sort_order"?}` | Shop |
| `DELETE /v1/households/{hid}/shops/{shopId}` | | 204; its list items and products keep existing with `shop_id: null` |
| `GET /v1/households/{hid}/catalog-items` | | `[CatalogItem]` by name (the household's products) |
| `POST /v1/households/{hid}/catalog-items` | `{"name"(1–200), "default_unit"?(≤50), "shop_id"?}` | 201 new product · 200 existing product (name matched case-insensitively; hints updated when sent) |
| `PATCH /v1/households/{hid}/catalog-items/{itemId}` | `{"name"?, "default_unit"?(nullable), "shop_id"?(nullable)}` | CatalogItem · 409 when the name is taken |
| `DELETE /v1/households/{hid}/catalog-items/{itemId}` | | 204 (list items keep their name, `catalog_item_id` becomes null) |
| `GET /v1/households/{hid}/items` | | `[ShoppingListItem]`, oldest first, needed and bought |
| `POST /v1/households/{hid}/items` | `{"id"?(UUID), "name"(1–200), "shop_id"?, "catalog_item_id"?, "quantity"?(≤50)}` | 201 ShoppingListItem; 200 when `id` already exists (retry). The item is linked to the product of that name (created on first use; `catalog_item_id` picks one explicitly and supplies its name, `shop_id` and `default_unit` where the body has none). The product then remembers the `shop_id`/`quantity` used. Foreign references → 400. SSE also carries the `catalog_items` insert/update |
| `PATCH /v1/households/{hid}/items/{itemId}` | `{"name"?, "quantity"?(nullable), "shop_id"?(nullable; "move to shop"), "status"?}` | ShoppingListItem; `status` flips set/clear `bought_at` server-side |
| `DELETE /v1/households/{hid}/items/{itemId}` | | 204 |
| `DELETE /v1/households/{hid}/items?status=bought` | | 204 ("Clear recently bought"); without the query → 400 |
| `POST /v1/households/{hid}/items/checkout` | `{}` (everything in the basket) · `{"shop_id":"<id>"}` (one shop) · `{"shop_id":null}` (Unsorted) | `[ShoppingListItem]` now `bought` (SSE: one update each) |
| `GET /v1/households/{hid}/events` | | SSE stream, see below |
| `PUT /v1/me/push-tokens` | `{"token"(1–4096), "platform"("ios"\|"android")}` | 204 (upsert; a token re-registered by another user moves to the caller) |
| `DELETE /v1/me/push-tokens/{token}` | | 204, idempotent; only the caller's own registration is removed (call before signing out) |

Nulls are explicit (`"shop_id": null`), never omitted, except `role` which is omitted when not applicable.

## Realtime: `GET /v1/households/{hid}/events`

Server-Sent Events (`Content-Type: text/event-stream`), one stream per household, same bearer auth
and membership rule as the JSON routes. Frames:

```
event: ready
data: {"household_id":"…"}            first frame; clients (re)fetch items + shops on it

id: <event id>
event: change
data: {"id":"…","table":"shopping_list_items","type":"insert","row":{…},"actor":"<uid>"}

: ping                                 every 25 s (keeps Cloudflare's 100 s idle timeout away)
```

`table` ∈ `shopping_list_items | shops | catalog_items | households | household_members | household_invites`,
`type` ∈ `insert | update | delete`. `row` is the full resource for insert/update (same shape as the
REST responses, except Household rows carry no `role`); for delete it is `{"id"}`. Events are published only after the database commit. The stream closes when
the token expires, on disconnect, or when the client falls more than 64 events behind; clients
reconnect with a fresh token and refetch on `ready`. Android must use a read timeout of 0 on this
request; iOS URLSession needs a timeout longer than 25 s. See `testdata/golden/sse_change.json`.

## Push notifications (FCM HTTP v1)

Sent directly by the server when `FCM_SERVICE_ACCOUNT_FILE` points at an existing service-account
key (`roles/firebasemessaging.admin` only); otherwise push is disabled and the token routes still
work. Only two changes notify, and never the actor:

| Change | Body | Collapsing |
|---|---|---|
| `shopping_list_items` insert | `<Actor> added <name>` | inserts by the same actor within 5 s → `<Actor> added N items` |
| `household_members` insert (join) | `<Actor> joined <household>` | — |

Title = household name. `data` carries `household_id` and `type` (`shopping_list_items.insert` /
`household_members.insert`): clients suppress the banner when that household is on screen and
switch to it on tap. Android `collapse_key` / iOS `apns-collapse-id` = `hh-<hid>`, `thread-id` =
`<hid>`, channel `household`. Tokens FCM reports as `UNREGISTERED`, `INVALID_ARGUMENT` or
`SENDER_ID_MISMATCH` are deleted at once; tokens unseen for 60 days are pruned daily. Actor name =
`display_name`, else the email's local part. Pushes are best-effort: no retries, no queue beyond
64 pending changes.

## Typical flows

- **First launch**: `GET /v1/households` → `[]` → onboarding → `POST /v1/households` or `POST /v1/households/join` → select the returned household → `GET …/items` + `GET …/shops` → open `…/events`.
- **List screen**: group `needed` items by `shop_id` in `shops` order, `null` last ("Unsorted"); `bought` items go under "Recently bought".
- **Shop detail "To list"**: `POST …/items {"name": catalog.name, "catalog_item_id": catalog.id}` (server fills `shop_id` and `quantity`).
- **Settings invite**: newest invite with `revoked_at == null`; `POST …/invites` to regenerate, then revoke the old one.
