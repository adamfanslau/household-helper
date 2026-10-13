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

// CreateItem adds a list item. A catalog reference must belong to a shop of the
// household; it supplies the shop and, when the client sent no quantity, the
// catalog default_unit (the Expo app dropped it). Returns created=false when the
// client id already exists in this household (idempotent retry).
func (db *DB) CreateItem(ctx context.Context, hid, uid string, in NewItem) (ListItem, bool, error) {
	var out ListItem
	created := true
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if in.ID != "" {
			existing, err := db.getItem(ctx, tx, hid, in.ID)
			if err == nil {
				out, created = existing, false
				return nil
			}
			if !errors.Is(err, ErrNotFound) {
				return err
			}
		}
		shopID, qty := in.ShopID, in.Quantity
		if in.CatalogItemID != nil {
			var catShop string
			var unit sql.NullString
			err := tx.QueryRowContext(ctx, `SELECT c.shop_id, c.default_unit FROM catalog_items c JOIN shops s ON s.id = c.shop_id
				WHERE c.id = ? AND s.household_id = ?`, *in.CatalogItemID, hid).Scan(&catShop, &unit)
			if errors.Is(err, sql.ErrNoRows) {
				return ErrInvalid
			}
			if err != nil {
				return err
			}
			if shopID == nil {
				shopID = &catShop
			} else if *shopID != catShop {
				return ErrInvalid
			}
			if qty == nil && unit.Valid && unit.String != "" {
				qty = &unit.String
			}
		} else if shopID != nil {
			if err := shopInHousehold(ctx, tx, hid, *shopID); err != nil {
				return err
			}
		}
		id := in.ID
		if id == "" {
			id = ids.New()
		}
		now := Now()
		if _, err := tx.ExecContext(ctx, `INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, 'needed', ?, ?, ?)`, id, hid, in.Name, nullStr(shopID), nullStr(in.CatalogItemID), nullStr(qty), uid, now, now); err != nil {
			return err
		}
		var err error
		out, err = db.getItem(ctx, tx, hid, id)
		return err
	})
	return out, created, err
}

// ItemPatch: Name/Status replace when non-nil; Quantity/ShopID are nullable optionals.
type ItemPatch struct {
	Name     *string
	Status   *string // needed | bought; the server sets/clears bought_at
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
