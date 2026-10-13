package httpapi

import (
	"bytes"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

var update = flag.Bool("update", false, "rewrite testdata/golden/*.json (make golden)")

func str(s string) *string { return &s }

// TestGolden pins the JSON wire shapes. iOS (ModelsDecodingTests) and Android
// (ModelsDecodingTest) decode these same files, so a tag change here must be
// followed by `make golden` and fixes in both clients (API.md "Contract").
func TestGolden(t *testing.T) {
	const (
		ts  = "2026-01-01T10:00:00.000Z"
		hid = "11111111-1111-4111-8111-111111111111"
		sid = "33333333-3333-4333-8333-000000000001"
		cid = "44444444-4444-4444-8444-000000000001"
	)
	fixtures := map[string]any{
		"me":           store.User{ID: "dev-alice", Email: "alice@dev.local", DisplayName: "Alice", Provider: "password", CreatedAt: ts, LastSeenAt: ts},
		"household":    store.Household{ID: hid, Name: "Mock Household", CreatedBy: str("dev-alice"), CreatedAt: ts, UpdatedAt: ts, Role: "owner"},
		"invite":       store.Invite{ID: "66666666-6666-4666-8666-000000000001", HouseholdID: hid, Code: "MOCK1234", CreatedBy: str("dev-alice"), CreatedAt: ts},
		"shop":         store.Shop{ID: sid, HouseholdID: hid, Name: "Trader Joe's", SortOrder: 0, CreatedAt: ts, UpdatedAt: ts, NeededCount: 2},
		"catalog_item": store.CatalogItem{ID: cid, ShopID: sid, Name: "Milk", DefaultUnit: str("1 gal"), CreatedAt: ts, UpdatedAt: ts},
		"shopping_list_item": store.ListItem{ID: "55555555-5555-4555-8555-000000000001", HouseholdID: hid, Name: "Milk", ShopID: str(sid), CatalogItemID: str(cid),
			Quantity: str("1 gal"), Status: "bought", AddedBy: str("dev-alice"), CreatedAt: ts, UpdatedAt: ts, BoughtAt: str(ts)},
		"sse_change": sse.Event{ID: "0199c700-0000-7000-8000-000000000001", Table: "shopping_list_items", Type: "update", Actor: "dev-bob",
			Row: store.ListItem{ID: "55555555-5555-4555-8555-000000000001", HouseholdID: hid, Name: "Milk", ShopID: str(sid), CatalogItemID: str(cid),
				Quantity: str("1 gal"), Status: "bought", AddedBy: str("dev-alice"), CreatedAt: ts, UpdatedAt: ts, BoughtAt: str(ts)}},
		"error": errorBody{Error: errorDetail{Code: "invalid_request", Message: "invalid item", Fields: map[string]string{"name": "required, 1-200 characters"}}},
	}
	for name, v := range fixtures {
		t.Run(name, func(t *testing.T) {
			got, err := json.MarshalIndent(v, "", "  ")
			if err != nil {
				t.Fatal(err)
			}
			got = append(got, '\n')
			path := filepath.Join("testdata", "golden", name+".json")
			if *update {
				if err := os.WriteFile(path, got, 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("%v (run `make golden` to create it)", err)
			}
			if !bytes.Equal(got, want) {
				t.Fatalf("%s drifted from the golden file; if intended, run `make golden`, update API.md and both client decode tests.\n got: %s\nwant: %s", name, got, want)
			}
		})
	}
}
