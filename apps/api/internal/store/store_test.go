package store

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func openTest(t *testing.T) *DB {
	t.Helper()
	db, err := Open(context.Background(), filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func exec(t *testing.T, db *DB, q string, args ...any) {
	t.Helper()
	if _, err := db.W.ExecContext(context.Background(), q, args...); err != nil {
		t.Fatalf("%s: %v", q, err)
	}
}

func execErr(t *testing.T, db *DB, want string, q string, args ...any) {
	t.Helper()
	_, err := db.W.ExecContext(context.Background(), q, args...)
	if err == nil || !strings.Contains(err.Error(), want) {
		t.Fatalf("%s: expected error containing %q, got %v", q, want, err)
	}
}

func count(t *testing.T, db *DB, q string, args ...any) int {
	t.Helper()
	var n int
	if err := db.R.QueryRowContext(context.Background(), q, args...).Scan(&n); err != nil {
		t.Fatalf("%s: %v", q, err)
	}
	return n
}

// seed inserts one user, household, membership, shop, catalog item and list item with raw SQL.
func seed(t *testing.T, db *DB) {
	t.Helper()
	now := Now()
	exec(t, db, `INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at) VALUES ('u1','a@x','A','google',?,?)`, now, now)
	exec(t, db, `INSERT INTO households (id, name, created_by, created_at, updated_at) VALUES ('h1','Home','u1',?,?)`, now, now)
	exec(t, db, `INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES ('h1','u1','owner',?)`, now)
	exec(t, db, `INSERT INTO household_invites (id, household_id, code, created_by, created_at) VALUES ('i1','h1','ABCD2345','u1',?)`, now)
	exec(t, db, `INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES ('s1','h1','TJ',0,?,?)`, now, now)
	exec(t, db, `INSERT INTO catalog_items (id, household_id, shop_id, name, default_unit, created_at, updated_at) VALUES ('c1','h1','s1','Milk','1 gal',?,?)`, now, now)
	exec(t, db, `INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at)
	             VALUES ('l1','h1','Milk','s1','c1','1 gal','needed','u1',?,?)`, now, now)
}

func TestMigrationsIdempotent(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	for i := 0; i < 3; i++ {
		if err := db.Migrate(ctx); err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
	}
	v, err := db.AppliedMigrations(ctx)
	if err != nil || len(v) != 4 || v[0] != 1 || v[1] != 2 || v[2] != 3 || v[3] != 4 {
		t.Fatalf("applied = %v, %v", v, err)
	}
	var mode string
	if err := db.W.QueryRowContext(ctx, "PRAGMA journal_mode").Scan(&mode); err != nil || mode != "wal" {
		t.Fatalf("journal_mode = %q, %v", mode, err)
	}
	var fk int
	if err := db.R.QueryRowContext(ctx, "PRAGMA foreign_keys").Scan(&fk); err != nil || fk != 1 {
		t.Fatalf("foreign_keys = %d, %v", fk, err)
	}
	path := filepath.Join(t.TempDir(), "re.db")
	for i := 0; i < 2; i++ {
		d, err := Open(ctx, path)
		if err != nil {
			t.Fatal(err)
		}
		d.Close()
	}
}

func TestChecks(t *testing.T) {
	db := openTest(t)
	seed(t, db)
	now := Now()
	execErr(t, db, "CHECK", `INSERT INTO households (id, name, created_at, updated_at) VALUES ('h2','',?,?)`, now, now)
	execErr(t, db, "CHECK", `INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES ('h1','u1','admin',?)`, now)
	execErr(t, db, "CHECK", `INSERT INTO shopping_list_items (id, household_id, name, status, created_at, updated_at) VALUES ('l2','h1','Eggs','maybe',?,?)`, now, now)
	exec(t, db, `INSERT INTO shopping_list_items (id, household_id, name, status, created_at, updated_at) VALUES ('l3','h1','Jam','in_basket',?,?)`, now, now)
	execErr(t, db, "CHECK", `UPDATE shopping_list_items SET bought_at = ? WHERE id = 'l3'`, now) // in_basket is not bought
	// status and bought_at must agree.
	execErr(t, db, "CHECK", `UPDATE shopping_list_items SET status = 'bought' WHERE id = 'l1'`)
	execErr(t, db, "CHECK", `UPDATE shopping_list_items SET bought_at = ? WHERE id = 'l1'`, now)
	exec(t, db, `UPDATE shopping_list_items SET status = 'bought', bought_at = ? WHERE id = 'l1'`, now)
	exec(t, db, `UPDATE shopping_list_items SET status = 'needed', bought_at = NULL WHERE id = 'l1'`)
	// Invite codes are unique and exactly 8 chars.
	execErr(t, db, "UNIQUE", `INSERT INTO household_invites (id, household_id, code, created_at) VALUES ('i2','h1','ABCD2345',?)`, now)
	execErr(t, db, "CHECK", `INSERT INTO household_invites (id, household_id, code, created_at) VALUES ('i3','h1','SHORT',?)`, now)
	// Foreign keys are enforced.
	execErr(t, db, "FOREIGN KEY", `INSERT INTO shops (id, household_id, name, created_at, updated_at) VALUES ('s9','nope','X',?,?)`, now, now)
}

func TestCascadesAndSetNull(t *testing.T) {
	db := openTest(t)
	seed(t, db)
	exec(t, db, `DELETE FROM shops WHERE id = 's1'`)
	var catShop any
	if err := db.R.QueryRowContext(context.Background(), `SELECT shop_id FROM catalog_items WHERE id = 'c1'`).Scan(&catShop); err != nil || catShop != nil {
		t.Fatalf("product should survive the shop with shop_id NULL, got %v %v", catShop, err)
	}
	var shop, cat any
	if err := db.R.QueryRowContext(context.Background(), `SELECT shop_id, catalog_item_id FROM shopping_list_items WHERE id = 'l1'`).Scan(&shop, &cat); err != nil {
		t.Fatal(err)
	}
	if shop != nil || cat == nil {
		t.Fatalf("list item should keep its product and lose the shop, got %v %v", shop, cat)
	}
	execErr(t, db, "UNIQUE", `INSERT INTO catalog_items (id, household_id, name, created_at, updated_at) VALUES ('c2','h1','milk',?,?)`, Now(), Now())
	exec(t, db, `DELETE FROM catalog_items WHERE id = 'c1'`)
	if err := db.R.QueryRowContext(context.Background(), `SELECT catalog_item_id FROM shopping_list_items WHERE id = 'l1'`).Scan(&cat); err != nil || cat != nil {
		t.Fatalf("deleting a product should null the link, got %v %v", cat, err)
	}
	exec(t, db, `DELETE FROM households WHERE id = 'h1'`)
	for _, tbl := range []string{"household_members", "household_invites", "shops", "catalog_items", "shopping_list_items"} {
		if n := count(t, db, `SELECT COUNT(*) FROM `+tbl); n != 0 {
			t.Fatalf("%s should cascade with the household, got %d", tbl, n)
		}
	}
	if n := count(t, db, `SELECT COUNT(*) FROM users`); n != 1 {
		t.Fatal("users must survive a household delete")
	}
}

func TestPushTokens(t *testing.T) {
	db := openTest(t)
	ctx := context.Background()
	seed(t, db)
	exec(t, db, `INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at) VALUES ('u2','b@x','','google',?,?)`, Now(), Now())
	exec(t, db, `INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES ('h1','u2','member',?)`, Now())
	if err := db.UpsertPushToken(ctx, "t-u1", "u1", "ios"); err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertPushToken(ctx, "t-u2", "u2", "android"); err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertPushToken(ctx, "t-u2", "u2", "web"); err == nil {
		t.Fatal("platform CHECK should reject web")
	}
	rows, err := db.HouseholdPushTokens(ctx, "h1", "u1")
	if err != nil || len(rows) != 1 || rows[0].Token != "t-u2" || rows[0].Platform != "android" {
		t.Fatalf("tokens minus u1: %+v, %v", rows, err)
	}
	// Stale rows are pruned; fresh ones stay.
	exec(t, db, `UPDATE push_tokens SET last_seen_at = '2020-01-01T00:00:00.000Z' WHERE token = 't-u1'`)
	n, err := db.PrunePushTokens(ctx, 60*24*time.Hour)
	if err != nil || n != 1 {
		t.Fatalf("pruned %d, %v", n, err)
	}
	// Deleting the user cascades.
	exec(t, db, `DELETE FROM users WHERE id = 'u2'`)
	if rows, _ = db.HouseholdPushTokens(ctx, "h1", ""); len(rows) != 0 {
		t.Fatalf("cascade: %+v", rows)
	}
	if name, err := db.HouseholdName(ctx, "h1"); err != nil || name == "" {
		t.Fatalf("household name %q, %v", name, err)
	}
	if name, err := db.HouseholdName(ctx, "nope"); err != nil || name != "" {
		t.Fatalf("missing household name %q, %v", name, err)
	}
}

// The 0003 rebuild must keep list items linked to their products and drop per-shop duplicates.
func TestProductsMigrationKeepsLinks(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.db")
	db, err := openNoMigrate(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	ctx := context.Background()
	if err := db.migrateUpTo(ctx, 2); err != nil {
		t.Fatal(err)
	}
	now := Now()
	exec(t, db, `INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at) VALUES ('u1','a@x','A','google',?,?)`, now, now)
	exec(t, db, `INSERT INTO households (id, name, created_by, created_at, updated_at) VALUES ('h1','Home','u1',?,?)`, now, now)
	exec(t, db, `INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES ('s1','h1','TJ',0,?,?), ('s2','h1','Costco',1,?,?)`, now, now, now, now)
	exec(t, db, `INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES ('c1','s1','Milk','1 gal','2026-01-01T00:00:00.000Z',?), ('c2','s2','milk',NULL,'2026-01-02T00:00:00.000Z',?), ('c3','s2','Towels',NULL,?,?)`, now, now, now, now)
	exec(t, db, `INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, status, created_at, updated_at) VALUES ('l1','h1','Milk','s1','c1','needed',?,?), ('l2','h1','Towels','s2','c3','needed',?,?)`, now, now, now, now)
	if err := db.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	if n := count(t, db, `SELECT COUNT(*) FROM catalog_items`); n != 2 {
		t.Fatalf("duplicate product should be merged, got %d rows", n)
	}
	var hid string
	var link any
	if err := db.R.QueryRowContext(ctx, `SELECT c.household_id, l.catalog_item_id FROM shopping_list_items l JOIN catalog_items c ON c.id = l.catalog_item_id WHERE l.id = 'l1'`).Scan(&hid, &link); err != nil || hid != "h1" || link != "c1" {
		t.Fatalf("link lost across the rebuild: %v %v %v", hid, link, err)
	}
	// The FK still targets the live table: deleting the product nulls the link.
	exec(t, db, `DELETE FROM catalog_items WHERE id = 'c3'`)
	if err := db.R.QueryRowContext(ctx, `SELECT catalog_item_id FROM shopping_list_items WHERE id = 'l2'`).Scan(&link); err != nil || link != nil {
		t.Fatalf("FK should follow the rebuilt table, got %v %v", link, err)
	}
	var fk int
	if err := db.R.QueryRowContext(ctx, "PRAGMA foreign_key_check").Scan(&fk); err == nil {
		t.Fatalf("foreign_key_check reported violations")
	}
}
