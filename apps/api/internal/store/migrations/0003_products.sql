-- Products are household-wide, not per shop: catalog_items gains household_id, shop_id becomes
-- the last shop the product was added for (nullable) and default_unit the last quantity used.
-- SQLite cannot relax NOT NULL in place, so the table is rebuilt. Dropping the old table fires
-- shopping_list_items' ON DELETE SET NULL, so the links are saved first and restored after
-- (remapped onto the surviving product when a name existed in several shops).

CREATE TEMP TABLE product_map AS
  SELECT c.id AS old_id, s.household_id AS household_id,
         FIRST_VALUE(c.id) OVER (PARTITION BY s.household_id, lower(c.name) ORDER BY c.created_at, c.id) AS new_id
  FROM catalog_items c JOIN shops s ON s.id = c.shop_id;
CREATE TEMP TABLE item_links AS
  SELECT l.id AS item_id, m.new_id AS catalog_item_id
  FROM shopping_list_items l JOIN product_map m ON m.old_id = l.catalog_item_id;

CREATE TABLE catalog_items_new (
  id           TEXT PRIMARY KEY,
  household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  shop_id      TEXT REFERENCES shops(id) ON DELETE SET NULL,   -- last shop used
  name         TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  default_unit TEXT,                                            -- last quantity used
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
INSERT INTO catalog_items_new (id, household_id, shop_id, name, default_unit, created_at, updated_at)
  SELECT c.id, m.household_id, c.shop_id, c.name, c.default_unit, c.created_at, c.updated_at
  FROM catalog_items c JOIN product_map m ON m.old_id = c.id
  WHERE m.old_id = m.new_id;

DROP TABLE catalog_items;
ALTER TABLE catalog_items_new RENAME TO catalog_items;
CREATE UNIQUE INDEX catalog_items_household_name_idx ON catalog_items(household_id, name COLLATE NOCASE);
CREATE INDEX catalog_items_shop_id_idx ON catalog_items(shop_id);

UPDATE shopping_list_items
  SET catalog_item_id = (SELECT catalog_item_id FROM item_links WHERE item_links.item_id = shopping_list_items.id)
  WHERE id IN (SELECT item_id FROM item_links);
DROP TABLE item_links;
DROP TABLE product_map;
