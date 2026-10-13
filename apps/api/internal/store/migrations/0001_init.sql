-- Household Helper schema, ported from the Supabase migrations (0001_schema.sql).
-- TEXT UUIDs (generated in Go), TEXT RFC 3339 UTC timestamps with milliseconds.
-- Authorization is enforced by the API (requireMember + row scoping), not here.

CREATE TABLE users (
  id           TEXT PRIMARY KEY,                 -- Firebase uid
  email        TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  provider     TEXT NOT NULL DEFAULT '',
  created_at   TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE households (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  created_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE household_members (
  household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role         TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
  joined_at    TEXT NOT NULL,
  PRIMARY KEY (household_id, user_id)
);
CREATE INDEX household_members_user_id_idx ON household_members(user_id);

CREATE TABLE household_invites (
  id           TEXT PRIMARY KEY,
  household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  code         TEXT NOT NULL UNIQUE CHECK (length(code) = 8),
  created_by   TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at   TEXT NOT NULL,
  expires_at   TEXT,
  revoked_at   TEXT
);
CREATE INDEX household_invites_household_id_idx ON household_invites(household_id);

CREATE TABLE shops (
  id           TEXT PRIMARY KEY,
  household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name         TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  sort_order   INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
CREATE INDEX shops_household_id_idx ON shops(household_id);

CREATE TABLE catalog_items (
  id           TEXT PRIMARY KEY,
  shop_id      TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name         TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 100),
  default_unit TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
CREATE INDEX catalog_items_shop_id_idx ON catalog_items(shop_id);

CREATE TABLE shopping_list_items (
  id              TEXT PRIMARY KEY,
  household_id    TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name            TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  shop_id         TEXT REFERENCES shops(id) ON DELETE SET NULL,
  catalog_item_id TEXT REFERENCES catalog_items(id) ON DELETE SET NULL,
  quantity        TEXT,
  status          TEXT NOT NULL DEFAULT 'needed' CHECK (status IN ('needed', 'bought')),
  added_by        TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  bought_at       TEXT,
  -- bought_at is set by the server exactly when status flips to bought (the Expo app set it client-side).
  CHECK ((status = 'bought') = (bought_at IS NOT NULL))
);
CREATE INDEX shopping_list_items_household_id_idx ON shopping_list_items(household_id);
CREATE INDEX shopping_list_items_household_status_idx ON shopping_list_items(household_id, status);
CREATE INDEX shopping_list_items_shop_id_idx ON shopping_list_items(shop_id);
