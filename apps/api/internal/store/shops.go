package store

import (
	"context"
	"database/sql"
	"errors"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
)

type Shop struct {
	ID          string `json:"id"`
	HouseholdID string `json:"household_id"`
	Name        string `json:"name"`
	SortOrder   int    `json:"sort_order"`
	CreatedAt   string `json:"created_at"`
	UpdatedAt   string `json:"updated_at"`
	NeededCount int    `json:"needed_count"` // computed: list items with status=needed in this shop
}

type CatalogItem struct {
	ID          string  `json:"id"`
	ShopID      string  `json:"shop_id"`
	Name        string  `json:"name"`
	DefaultUnit *string `json:"default_unit"`
	CreatedAt   string  `json:"created_at"`
	UpdatedAt   string  `json:"updated_at"`
}

const shopCols = `s.id, s.household_id, s.name, s.sort_order, s.created_at, s.updated_at,
	(SELECT COUNT(*) FROM shopping_list_items i WHERE i.shop_id = s.id AND i.status = 'needed')`

func scanShop(row interface{ Scan(...any) error }) (Shop, error) {
	var s Shop
	err := row.Scan(&s.ID, &s.HouseholdID, &s.Name, &s.SortOrder, &s.CreatedAt, &s.UpdatedAt, &s.NeededCount)
	if errors.Is(err, sql.ErrNoRows) {
		return s, ErrNotFound
	}
	return s, err
}

// ListShops returns the household's shops in sort_order (ties by creation).
func (db *DB) ListShops(ctx context.Context, hid string) ([]Shop, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT `+shopCols+` FROM shops s WHERE s.household_id = ? ORDER BY s.sort_order, s.created_at, s.id`, hid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Shop{}
	for rows.Next() {
		s, err := scanShop(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (db *DB) getShop(ctx context.Context, q querier, hid, id string) (Shop, error) {
	return scanShop(q.QueryRowContext(ctx, `SELECT `+shopCols+` FROM shops s WHERE s.id = ? AND s.household_id = ?`, id, hid))
}

func (db *DB) GetShop(ctx context.Context, hid, id string) (Shop, error) {
	return db.getShop(ctx, db.R, hid, id)
}

// CreateShop appends the shop (sort_order = max + 1, computed here, not by the client).
func (db *DB) CreateShop(ctx context.Context, hid, name string) (Shop, error) {
	now := Now()
	s := Shop{ID: ids.New(), HouseholdID: hid, Name: name, CreatedAt: now, UpdatedAt: now}
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if err := tx.QueryRowContext(ctx, `SELECT COALESCE(MAX(sort_order), -1) + 1 FROM shops WHERE household_id = ?`, hid).Scan(&s.SortOrder); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`,
			s.ID, hid, name, s.SortOrder, now, now)
		return err
	})
	return s, err
}

type ShopPatch struct {
	Name      *string
	SortOrder *int
}

func (db *DB) UpdateShop(ctx context.Context, hid, id string, p ShopPatch) (Shop, error) {
	var out Shop
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		cur, err := db.getShop(ctx, tx, hid, id)
		if err != nil {
			return err
		}
		if p.Name != nil {
			cur.Name = *p.Name
		}
		if p.SortOrder != nil {
			cur.SortOrder = *p.SortOrder
		}
		if _, err := tx.ExecContext(ctx, `UPDATE shops SET name = ?, sort_order = ?, updated_at = ? WHERE id = ? AND household_id = ?`,
			cur.Name, cur.SortOrder, Now(), id, hid); err != nil {
			return err
		}
		out, err = db.getShop(ctx, tx, hid, id)
		return err
	})
	return out, err
}

// DeleteShop removes the shop; its catalog cascades and list items keep existing with shop_id NULL (Unsorted).
func (db *DB) DeleteShop(ctx context.Context, hid, id string) error {
	res, err := db.W.ExecContext(ctx, `DELETE FROM shops WHERE id = ? AND household_id = ?`, id, hid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

const catalogCols = `c.id, c.shop_id, c.name, c.default_unit, c.created_at, c.updated_at`

func scanCatalog(row interface{ Scan(...any) error }) (CatalogItem, error) {
	var c CatalogItem
	var unit sql.NullString
	err := row.Scan(&c.ID, &c.ShopID, &c.Name, &unit, &c.CreatedAt, &c.UpdatedAt)
	c.DefaultUnit = ptrS(unit)
	if errors.Is(err, sql.ErrNoRows) {
		return c, ErrNotFound
	}
	return c, err
}

// ListCatalog returns a shop's catalog sorted by name; ErrNotFound when the shop is not in hid.
func (db *DB) ListCatalog(ctx context.Context, hid, shopID string) ([]CatalogItem, error) {
	if _, err := db.GetShop(ctx, hid, shopID); err != nil {
		return nil, err
	}
	rows, err := db.R.QueryContext(ctx, `SELECT `+catalogCols+` FROM catalog_items c WHERE c.shop_id = ? ORDER BY c.name COLLATE NOCASE, c.id`, shopID)
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

func (db *DB) CreateCatalogItem(ctx context.Context, hid, shopID, name string, unit *string) (CatalogItem, error) {
	now := Now()
	c := CatalogItem{ID: ids.New(), ShopID: shopID, Name: name, DefaultUnit: unit, CreatedAt: now, UpdatedAt: now}
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := db.getShop(ctx, tx, hid, shopID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`,
			c.ID, shopID, name, nullStr(unit), now, now)
		return err
	})
	return c, err
}

func (db *DB) DeleteCatalogItem(ctx context.Context, hid, shopID, id string) error {
	res, err := db.W.ExecContext(ctx, `DELETE FROM catalog_items WHERE id = ? AND shop_id = ?
		AND shop_id IN (SELECT id FROM shops WHERE household_id = ?)`, id, shopID, hid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}
