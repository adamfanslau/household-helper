package store

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
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
	exec(t, db, `INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES ('c1','s1','Milk','1 gal',?,?)`, now, now)
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
	if err != nil || len(v) != 1 || v[0] != 1 {
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
	if n := count(t, db, `SELECT COUNT(*) FROM catalog_items`); n != 0 {
		t.Fatalf("catalog items should cascade with the shop, got %d", n)
	}
	var shop, cat any
	if err := db.R.QueryRowContext(context.Background(), `SELECT shop_id, catalog_item_id FROM shopping_list_items WHERE id = 'l1'`).Scan(&shop, &cat); err != nil {
		t.Fatal(err)
	}
	if shop != nil || cat != nil {
		t.Fatalf("list item should keep existing with shop/catalog set to NULL, got %v %v", shop, cat)
	}
	exec(t, db, `DELETE FROM households WHERE id = 'h1'`)
	for _, tbl := range []string{"household_members", "household_invites", "shops", "shopping_list_items"} {
		if n := count(t, db, `SELECT COUNT(*) FROM `+tbl); n != 0 {
			t.Fatalf("%s should cascade with the household, got %d", tbl, n)
		}
	}
	if n := count(t, db, `SELECT COUNT(*) FROM users`); n != 1 {
		t.Fatal("users must survive a household delete")
	}
}
