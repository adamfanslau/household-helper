// Package devseed fills the local stack with the data the Expo mock mode had
// (apps/mobile/lib/mock/seed.ts): two emulator users and one household with shops,
// a catalog and a list. Fixed ids keep deep links and verify scripts stable.
// Only reachable when config allows DEV_SEED (loopback, non-production port).
package devseed

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// Fixed identifiers (valid UUID shape, obviously fake).
const (
	UIDAlice = "dev-alice"
	UIDBob   = "dev-bob"

	HouseholdMock      = "11111111-1111-4111-8111-111111111111"
	HouseholdNeighbors = "22222222-2222-4222-8222-222222222222"
	InviteMock         = "MOCK1234"
	InviteNeighbors    = "JOIN5678"

	ShopTJ       = "33333333-3333-4333-8333-000000000001"
	ShopCostco   = "33333333-3333-4333-8333-000000000002"
	ShopPharmacy = "33333333-3333-4333-8333-000000000003"

	CatalogMilk    = "44444444-4444-4444-8444-000000000001"
	CatalogEggs    = "44444444-4444-4444-8444-000000000002"
	CatalogBananas = "44444444-4444-4444-8444-000000000003"
	CatalogTowels  = "44444444-4444-4444-8444-000000000004"
	CatalogChicken = "44444444-4444-4444-8444-000000000005"

	ItemMilk      = "55555555-5555-4555-8555-000000000001"
	ItemBananas   = "55555555-5555-4555-8555-000000000002"
	ItemTowels    = "55555555-5555-4555-8555-000000000003"
	ItemBatteries = "55555555-5555-4555-8555-000000000004"
	ItemEggs      = "55555555-5555-4555-8555-000000000005"

	Password = "password"
)

type user struct{ UID, Email, Name string }

var Users = []user{{UIDAlice, "alice@dev.local", "Alice"}, {UIDBob, "bob@dev.local", "Bob"}}

// Run ensures the emulator users exist (every start: the emulator forgets them on
// restart) and inserts the rows when the households table is empty.
func Run(ctx context.Context, db *store.DB, emulatorURL, projectID string, log *slog.Logger) error {
	if err := EnsureEmulatorUsers(ctx, emulatorURL, projectID); err != nil {
		return fmt.Errorf("emulator users: %w", err)
	}
	var n int
	if err := db.R.QueryRowContext(ctx, `SELECT COUNT(*) FROM households`).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		log.Info("dev seed ready", "rows", "db not empty, skipped (make dev-reset for a fresh seed)", "users", "alice@dev.local bob@dev.local", "password", Password, "invites", InviteMock+" "+InviteNeighbors)
		return nil
	}
	if err := db.Tx(ctx, func(tx *sql.Tx) error { return insertRows(ctx, tx) }); err != nil {
		return fmt.Errorf("seed rows: %w", err)
	}
	log.Info("dev seed ready", "rows", "inserted", "users", "alice@dev.local bob@dev.local", "password", Password,
		"invites", InviteMock+" (Mock Household, alice owner) "+InviteNeighbors+" (The Neighbors, bob owner)",
		"household", HouseholdMock, "shop_tj", ShopTJ)
	return nil
}

// EnsureEmulatorUsers creates alice and bob with fixed uids through the emulator's
// admin endpoint (Authorization: Bearer owner). Duplicates are fine.
func EnsureEmulatorUsers(ctx context.Context, emulatorURL, projectID string) error {
	client := &http.Client{Timeout: 10 * time.Second}
	url := strings.TrimRight(emulatorURL, "/") + "/identitytoolkit.googleapis.com/v1/projects/" + projectID + "/accounts"
	for _, u := range Users {
		body, _ := json.Marshal(map[string]any{"localId": u.UID, "email": u.Email, "password": Password, "displayName": u.Name, "emailVerified": true})
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer owner")
		req.Header.Set("Content-Type", "application/json")
		res, err := client.Do(req)
		if err != nil {
			return err
		}
		resBody, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
		res.Body.Close()
		if res.StatusCode == http.StatusOK {
			continue
		}
		msg := string(resBody)
		if strings.Contains(msg, "DUPLICATE_LOCAL_ID") || strings.Contains(msg, "EMAIL_EXISTS") {
			continue
		}
		return fmt.Errorf("%s: %d %s", u.Email, res.StatusCode, strings.TrimSpace(msg))
	}
	return nil
}

func insertRows(ctx context.Context, tx *sql.Tx) error {
	// Fixed timestamps keep created_at ordering deterministic (as the Expo seed did).
	t := func(min int) string {
		return time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC).Add(time.Duration(min) * time.Minute).Format("2006-01-02T15:04:05.000Z07:00")
	}
	stmts := []struct {
		q    string
		args []any
	}{
		{`INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at) VALUES (?, ?, ?, 'password', ?, ?)`, []any{UIDAlice, "alice@dev.local", "Alice", t(0), t(0)}},
		{`INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at) VALUES (?, ?, ?, 'password', ?, ?)`, []any{UIDBob, "bob@dev.local", "Bob", t(0), t(0)}},
		{`INSERT INTO households (id, name, created_by, created_at, updated_at) VALUES (?, 'Mock Household', ?, ?, ?)`, []any{HouseholdMock, UIDAlice, t(0), t(0)}},
		{`INSERT INTO households (id, name, created_by, created_at, updated_at) VALUES (?, 'The Neighbors', ?, ?, ?)`, []any{HouseholdNeighbors, UIDBob, t(1), t(1)}},
		{`INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)`, []any{HouseholdMock, UIDAlice, t(0)}},
		{`INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)`, []any{HouseholdNeighbors, UIDBob, t(1)}},
		{`INSERT INTO household_invites (id, household_id, code, created_by, created_at) VALUES ('66666666-6666-4666-8666-000000000001', ?, ?, ?, ?)`, []any{HouseholdMock, InviteMock, UIDAlice, t(2)}},
		{`INSERT INTO household_invites (id, household_id, code, created_by, created_at) VALUES ('66666666-6666-4666-8666-000000000002', ?, ?, ?, ?)`, []any{HouseholdNeighbors, InviteNeighbors, UIDBob, t(2)}},
		{`INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES (?, ?, 'Trader Joe''s', 0, ?, ?)`, []any{ShopTJ, HouseholdMock, t(3), t(3)}},
		{`INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES (?, ?, 'Costco', 1, ?, ?)`, []any{ShopCostco, HouseholdMock, t(4), t(4)}},
		{`INSERT INTO shops (id, household_id, name, sort_order, created_at, updated_at) VALUES (?, ?, 'Pharmacy', 2, ?, ?)`, []any{ShopPharmacy, HouseholdMock, t(5), t(5)}},
		{`INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, 'Milk', '1 gal', ?, ?)`, []any{CatalogMilk, ShopTJ, t(6), t(6)}},
		{`INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, 'Eggs', NULL, ?, ?)`, []any{CatalogEggs, ShopTJ, t(7), t(7)}},
		{`INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, 'Bananas', NULL, ?, ?)`, []any{CatalogBananas, ShopTJ, t(8), t(8)}},
		{`INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, 'Paper towels', NULL, ?, ?)`, []any{CatalogTowels, ShopCostco, t(9), t(9)}},
		{`INSERT INTO catalog_items (id, shop_id, name, default_unit, created_at, updated_at) VALUES (?, ?, 'Chicken breast', NULL, ?, ?)`, []any{CatalogChicken, ShopCostco, t(10), t(10)}},
		{`INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, quantity, status, added_by, created_at, updated_at) VALUES (?, ?, 'Milk', ?, ?, '1 gal', 'needed', ?, ?, ?)`, []any{ItemMilk, HouseholdMock, ShopTJ, CatalogMilk, UIDAlice, t(11), t(11)}},
		{`INSERT INTO shopping_list_items (id, household_id, name, shop_id, status, added_by, created_at, updated_at) VALUES (?, ?, 'Bananas', ?, 'needed', ?, ?, ?)`, []any{ItemBananas, HouseholdMock, ShopTJ, UIDAlice, t(12), t(12)}},
		{`INSERT INTO shopping_list_items (id, household_id, name, shop_id, status, added_by, created_at, updated_at) VALUES (?, ?, 'Paper towels', ?, 'needed', ?, ?, ?)`, []any{ItemTowels, HouseholdMock, ShopCostco, UIDAlice, t(13), t(13)}},
		// shop_id NULL -> the "Unsorted" section.
		{`INSERT INTO shopping_list_items (id, household_id, name, status, added_by, created_at, updated_at) VALUES (?, ?, 'Batteries', 'needed', ?, ?, ?)`, []any{ItemBatteries, HouseholdMock, UIDAlice, t(14), t(14)}},
		// Already bought -> "Recently bought".
		{`INSERT INTO shopping_list_items (id, household_id, name, shop_id, catalog_item_id, status, added_by, created_at, updated_at, bought_at) VALUES (?, ?, 'Eggs', ?, ?, 'bought', ?, ?, ?, ?)`, []any{ItemEggs, HouseholdMock, ShopTJ, CatalogEggs, UIDAlice, t(15), t(16), t(16)}},
	}
	for _, s := range stmts {
		if _, err := tx.ExecContext(ctx, s.q, s.args...); err != nil {
			return fmt.Errorf("%s: %w", s.q[:40], err)
		}
	}
	return nil
}
