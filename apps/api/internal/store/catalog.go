package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
)

const catalogCols = `c.id, c.household_id, c.shop_id, c.name, c.default_unit, c.created_at, c.updated_at`

func scanCatalog(row interface{ Scan(...any) error }) (CatalogItem, error) {
	var c CatalogItem
	var shop, unit sql.NullString
	err := row.Scan(&c.ID, &c.HouseholdID, &shop, &c.Name, &unit, &c.CreatedAt, &c.UpdatedAt)
	c.ShopID, c.DefaultUnit = ptrS(shop), ptrS(unit)
	if errors.Is(err, sql.ErrNoRows) {
		return c, ErrNotFound
	}
	return c, err
}

// ListCatalog returns the household's products sorted by name.
func (db *DB) ListCatalog(ctx context.Context, hid string) ([]CatalogItem, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT `+catalogCols+` FROM catalog_items c WHERE c.household_id = ? ORDER BY c.name COLLATE NOCASE, c.id`, hid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CatalogItem{}
	for rows.Next() {
		c, err := scanCatalog(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (db *DB) getCatalogItem(ctx context.Context, q querier, hid, id string) (CatalogItem, error) {
	return scanCatalog(q.QueryRowContext(ctx, `SELECT `+catalogCols+` FROM catalog_items c WHERE c.id = ? AND c.household_id = ?`, id, hid))
}

func (db *DB) GetCatalogItem(ctx context.Context, hid, id string) (CatalogItem, error) {
	return db.getCatalogItem(ctx, db.R, hid, id)
}

// upsertCatalogItem finds the product by name (case-insensitive) or creates it, then remembers
// the quantity and shop when given. Returns created=true for a new row.
func (db *DB) upsertCatalogItem(ctx context.Context, tx *sql.Tx, hid, name string, unit, shopID *string) (CatalogItem, bool, error) {
	var existing CatalogItem
	err := func() error {
		c, err := scanCatalog(tx.QueryRowContext(ctx, `SELECT `+catalogCols+` FROM catalog_items c WHERE c.household_id = ? AND c.name = ? COLLATE NOCASE`, hid, name))
		existing = c
		return err
	}()
	now := Now()
	switch {
	case err == nil:
		set := `updated_at = ?`
		args := []any{now}
		if unit != nil {
			set += `, default_unit = ?`
			args = append(args, *unit)
		}
		if shopID != nil {
			set += `, shop_id = ?`
			args = append(args, *shopID)
		}
		args = append(args, existing.ID)
		if _, err := tx.ExecContext(ctx, `UPDATE catalog_items SET `+set+` WHERE id = ?`, args...); err != nil {
			return existing, false, err
		}
		c, err := db.getCatalogItem(ctx, tx, hid, existing.ID)
		return c, false, err
	case errors.Is(err, ErrNotFound):
		id := ids.New()
		if _, err := tx.ExecContext(ctx, `INSERT INTO catalog_items (id, household_id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
			id, hid, nullStr(shopID), name, nullStr(unit), now, now); err != nil {
			return existing, false, err
		}
		c, err := db.getCatalogItem(ctx, tx, hid, id)
		return c, true, err
	default:
		return existing, false, err
	}
}

// UpsertCatalogItem is the POST route: name is the key, unit/shop are optional hints.
func (db *DB) UpsertCatalogItem(ctx context.Context, hid, name string, unit, shopID *string) (CatalogItem, bool, error) {
	var out CatalogItem
	var created bool
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if shopID != nil {
			if err := shopInHousehold(ctx, tx, hid, *shopID); err != nil {
				return err
			}
		}
		var err error
		out, created, err = db.upsertCatalogItem(ctx, tx, hid, name, unit, shopID)
		return err
	})
	return out, created, err
}

// CatalogPatch: Name replaces when non-nil; DefaultUnit/ShopID are nullable optionals.
type CatalogPatch struct {
	Name        *string
	DefaultUnit Opt
	ShopID      Opt
}

func (db *DB) UpdateCatalogItem(ctx context.Context, hid, id string, p CatalogPatch) (CatalogItem, error) {
	var out CatalogItem
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := db.getCatalogItem(ctx, tx, hid, id); err != nil {
			return err
		}
		set := `updated_at = ?`
		args := []any{Now()}
		if p.Name != nil {
			set += `, name = ?`
			args = append(args, *p.Name)
		}
		if p.DefaultUnit.Set {
			set += `, default_unit = ?`
			args = append(args, nullStr(p.DefaultUnit.Value))
		}
		if p.ShopID.Set {
			if p.ShopID.Value != nil {
				if err := shopInHousehold(ctx, tx, hid, *p.ShopID.Value); err != nil {
					return err
				}
			}
			set += `, shop_id = ?`
			args = append(args, nullStr(p.ShopID.Value))
		}
		args = append(args, id)
		if _, err := tx.ExecContext(ctx, `UPDATE catalog_items SET `+set+` WHERE id = ?`, args...); err != nil {
			if isUniqueViolation(err) {
				return ErrConflict
			}
			return err
		}
		var err error
		out, err = db.getCatalogItem(ctx, tx, hid, id)
		return err
	})
	return out, err
}

func (db *DB) DeleteCatalogItem(ctx context.Context, hid, id string) error {
	res, err := db.W.ExecContext(ctx, `DELETE FROM catalog_items WHERE id = ? AND household_id = ?`, id, hid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}
