-- Shopping happens in two steps: tapping an item in the shop puts it "in the basket" (still on
-- the list, ticked); checkout marks the basket bought. SQLite cannot widen a CHECK in place, so
-- the table is rebuilt (nothing references shopping_list_items, so no FK juggling).
CREATE TABLE shopping_list_items_new (
  id              TEXT PRIMARY KEY,
  household_id    TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name            TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  shop_id         TEXT REFERENCES shops(id) ON DELETE SET NULL,
  catalog_item_id TEXT REFERENCES catalog_items(id) ON DELETE SET NULL,
  quantity        TEXT,
  status          TEXT NOT NULL DEFAULT 'needed' CHECK (status IN ('needed', 'in_basket', 'bought')),
  added_by        TEXT REFERENCES users(id) ON DELETE SET NULL,
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  bought_at       TEXT,
  CHECK ((status = 'bought') = (bought_at IS NOT NULL))
);
INSERT INTO shopping_list_items_new SELECT id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at, bought_at FROM shopping_list_items;
DROP TABLE shopping_list_items;
ALTER TABLE shopping_list_items_new RENAME TO shopping_list_items;
CREATE INDEX shopping_list_items_household_id_idx ON shopping_list_items(household_id);
CREATE INDEX shopping_list_items_household_status_idx ON shopping_list_items(household_id, status);
CREATE INDEX shopping_list_items_shop_id_idx ON shopping_list_items(shop_id);
