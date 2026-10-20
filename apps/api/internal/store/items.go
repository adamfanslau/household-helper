package store

import (
	"context"
	"database/sql"
	"errors"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
)

type ListItem struct {
	ID            string  `json:"id"`
	HouseholdID   string  `json:"household_id"`
	Name          string  `json:"name"`
	ShopID        *string `json:"shop_id"`
	CatalogItemID *string `json:"catalog_item_id"`
	Quantity      *string `json:"quantity"`
	Status        string  `json:"status"`
	AddedBy       *string `json:"added_by"`
	CreatedAt     string  `json:"created_at"`
	UpdatedAt     string  `json:"updated_at"`
	BoughtAt      *string `json:"bought_at"`
}

const itemCols = `id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at, bought_at`

func scanItem(row interface{ Scan(...any) error }) (ListItem, error) {
	var i ListItem
	var shop, cat, qty, by, bought sql.NullString
	err := row.Scan(&i.ID, &i.HouseholdID, &i.Name, &shop, &cat, &qty, &i.Status, &by, &i.CreatedAt, &i.UpdatedAt, &bought)
	i.ShopID, i.CatalogItemID, i.Quantity, i.AddedBy, i.BoughtAt = ptrS(shop), ptrS(cat), ptrS(qty), ptrS(by), ptrS(bought)
	if errors.Is(err, sql.ErrNoRows) {
		return i, ErrNotFound
	}
	return i, err
}

// ListItems returns every list item of the household (needed and bought), oldest first.
func (db *DB) ListItems(ctx context.Context, hid string) ([]ListItem, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT `+itemCols+` FROM shopping_list_items WHERE household_id = ? ORDER BY created_at, id`, hid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ListItem{}
	for rows.Next() {
		i, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

func (db *DB) getItem(ctx context.Context, q querier, hid, id string) (ListItem, error) {
	return scanItem(q.QueryRowContext(ctx, `SELECT `+itemCols+` FROM shopping_list_items WHERE id = ? AND household_id = ?`, id, hid))
}

func (db *DB) GetItem(ctx context.Context, hid, id string) (ListItem, error) {
	return db.getItem(ctx, db.R, hid, id)
}

// NewItem is what a client may send; ID is an optional client-generated UUID for idempotent retries.
type NewItem struct {
	ID            string
	Name          string
	ShopID        *string
	CatalogItemID *string
	Quantity      *string
}

// shopInHousehold returns ErrInvalid unless the shop belongs to hid.
func shopInHousehold(ctx context.Context, q querier, hid, shopID string) error {
	var n int
	if err := q.QueryRowContext(ctx, `SELECT COUNT(*) FROM shops WHERE id = ? AND household_id = ?`, shopID, hid).Scan(&n); err != nil {
		return err
	}
	if n == 0 {
		return ErrInvalid
	}
	return nil
}

// ItemCreated is the result of CreateItem: the list item plus the product it was linked to
// (found or created by name) so the caller can publish the catalog change too.
type ItemCreated struct {
	Item           ListItem
	Created        bool // false when the client id already existed (idempotent retry)
	Catalog        *CatalogItem
	CatalogCreated bool
}

// CreateItem adds a list item and keeps the household's product catalog in step: the item is
// linked to the product of the same name (created on first use), which remembers the shop
// and quantity just used; a catalog reference supplies those when the client sent none.
func (db *DB) CreateItem(ctx context.Context, hid, uid string, in NewItem) (ItemCreated, error) {
	var res ItemCreated
	res.Created = true
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if in.ID != "" {
			existing, err := db.getItem(ctx, tx, hid, in.ID)
			if err == nil {
				res.Item, res.Created = existing, false
				return nil
			}
			if !errors.Is(err, ErrNotFound) {
				return err
			}
		}
		shopID, qty := in.ShopID, in.Quantity
		if shopID != nil {
			if err := shopInHousehold(ctx, tx, hid, *shopID); err != nil {
				return err
			}
		}
		name := in.Name
		if in.CatalogItemID != nil {
			c, err := db.getCatalogItem(ctx, tx, hid, *in.CatalogItemID)
			if errors.Is(err, ErrNotFound) {
				return ErrInvalid
			}
			if err != nil {
				return err
			}
			name = c.Name
			if shopID == nil {
				shopID = c.ShopID
			}
			if qty == nil && c.DefaultUnit != nil && *c.DefaultUnit != "" {
				qty = c.DefaultUnit
			}
		}
		// Link to the product of that name (created on first use) and remember what was used.
		c, catCreated, err := db.upsertCatalogItem(ctx, tx, hid, name, qty, shopID)
		if err != nil {
			return err
		}
		res.Catalog, res.CatalogCreated = &c, catCreated
		name = c.Name // the product's spelling wins ("oat MILK" -> "Oat milk")
		id := in.ID
		if id == "" {
			id = ids.New()
		}
		now := Now()
		if _, err := tx.ExecContext(ctx, `INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, 'needed', ?, ?, ?)`, id, hid, name, nullStr(shopID), c.ID, nullStr(qty), uid, now, now); err != nil {
			return err
		}
		res.Item, err = db.getItem(ctx, tx, hid, id)
		return err
	})
	return res, err
}

// ItemPatch: Name/Status replace when non-nil; Quantity/ShopID are nullable optionals.
type ItemPatch struct {
	Name     *string
	Status   *string // needed | in_basket | bought; the server sets/clears bought_at
	Quantity Opt
	ShopID   Opt
}

func (db *DB) UpdateItem(ctx context.Context, hid, id string, p ItemPatch) (ListItem, error) {
	var out ListItem
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		cur, err := db.getItem(ctx, tx, hid, id)
		if err != nil {
			return err
		}
		if p.Name != nil {
			cur.Name = *p.Name
		}
		if p.Quantity.Set {
			cur.Quantity = p.Quantity.Value
		}
		if p.ShopID.Set {
			if p.ShopID.Value != nil {
				if err := shopInHousehold(ctx, tx, hid, *p.ShopID.Value); err != nil {
					return err
				}
			}
			cur.ShopID = p.ShopID.Value
		}
		now := Now()
		if p.Status != nil && *p.Status != cur.Status {
			cur.Status = *p.Status
			if cur.Status == "bought" {
				cur.BoughtAt = &now
			} else {
				cur.BoughtAt = nil
			}
		}
		if _, err := tx.ExecContext(ctx, `UPDATE shopping_list_items SET name = ?, quantity = ?, shop_id = ?, status = ?, bought_at = ?, updated_at = ?
			WHERE id = ? AND household_id = ?`, cur.Name, nullStr(cur.Quantity), nullStr(cur.ShopID), cur.Status, nullStr(cur.BoughtAt), now, id, hid); err != nil {
			return err
		}
		out, err = db.getItem(ctx, tx, hid, id)
		return err
	})
	return out, err
}

func (db *DB) DeleteItem(ctx context.Context, hid, id string) error {
	res, err := db.W.ExecContext(ctx, `DELETE FROM shopping_list_items WHERE id = ? AND household_id = ?`, id, hid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// Checkout marks the household's in-basket items bought: all of them (scope nil), one shop's
// (scope.Value = shop id) or the Unsorted ones (scope.Value = nil). Returns the updated rows.
func (db *DB) Checkout(ctx context.Context, hid string, scope Opt) ([]ListItem, error) {
	var out []ListItem
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		where := `household_id = ? AND status = 'in_basket'`
		args := []any{hid}
		if scope.Set {
			if scope.Value != nil {
				where += ` AND shop_id = ?`
				args = append(args, *scope.Value)
			} else {
				where += ` AND shop_id IS NULL`
			}
		}
		rows, err := tx.QueryContext(ctx, `SELECT id FROM shopping_list_items WHERE `+where, args...)
		if err != nil {
			return err
		}
		var ids []string
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			ids = append(ids, id)
		}
		rows.Close()
		now := Now()
		for _, id := range ids {
			if _, err := tx.ExecContext(ctx, `UPDATE shopping_list_items SET status = 'bought', bought_at = ?, updated_at = ? WHERE id = ?`, now, now, id); err != nil {
				return err
			}
			it, err := db.getItem(ctx, tx, hid, id)
			if err != nil {
				return err
			}
			out = append(out, it)
		}
		return nil
	})
	if out == nil {
		out = []ListItem{}
	}
	return out, err
}

// ClearBought deletes every bought item of the household and returns their ids (for SSE delete events).
func (db *DB) ClearBought(ctx context.Context, hid string) ([]string, error) {
	var deleted []string
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		rows, err := tx.QueryContext(ctx, `SELECT id FROM shopping_list_items WHERE household_id = ? AND status = 'bought'`, hid)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			deleted = append(deleted, id)
		}
		rows.Close()
		if len(deleted) == 0 {
			return nil
		}
		_, err = tx.ExecContext(ctx, `DELETE FROM shopping_list_items WHERE household_id = ? AND status = 'bought'`, hid)
		return err
	})
	return deleted, err
}
