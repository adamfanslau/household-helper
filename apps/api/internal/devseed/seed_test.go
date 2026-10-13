package devseed

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

func TestRunSeedsOnceAndAlwaysEnsuresUsers(t *testing.T) {
	var mu sync.Mutex
	var created []string
	emu := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer owner" || r.URL.Path != "/identitytoolkit.googleapis.com/v1/projects/demo/accounts" {
			t.Errorf("unexpected admin call %s %s auth=%q", r.Method, r.URL.Path, r.Header.Get("Authorization"))
		}
		var body map[string]any
		b, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(b, &body)
		mu.Lock()
		created = append(created, body["localId"].(string))
		mu.Unlock()
		_, _ = w.Write([]byte(`{"localId":"` + body["localId"].(string) + `"}`))
	}))
	defer emu.Close()

	db, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "seed.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	for i := 0; i < 2; i++ {
		if err := Run(context.Background(), db, emu.URL, "demo", log); err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
	}
	if len(created) != 4 || created[0] != UIDAlice || created[1] != UIDBob {
		t.Fatalf("emulator users must be ensured on every run: %v", created)
	}
	hs, err := db.ListHouseholds(context.Background(), UIDAlice)
	if err != nil || len(hs) != 1 || hs[0].ID != HouseholdMock || hs[0].Role != "owner" {
		t.Fatalf("alice households: %+v %v", hs, err)
	}
	if hs, _ := db.ListHouseholds(context.Background(), UIDBob); len(hs) != 1 || hs[0].ID != HouseholdNeighbors {
		t.Fatalf("bob should own only The Neighbors: %+v", hs)
	}
	var items, bought int
	_ = db.R.QueryRow(`SELECT COUNT(*) FROM shopping_list_items WHERE household_id = ?`, HouseholdMock).Scan(&items)
	_ = db.R.QueryRow(`SELECT COUNT(*) FROM shopping_list_items WHERE status = 'bought' AND bought_at IS NOT NULL`).Scan(&bought)
	if items != 5 || bought != 1 {
		t.Fatalf("items=%d bought=%d (second run must not duplicate)", items, bought)
	}
	if h, err := db.JoinHousehold(context.Background(), UIDBob, InviteMock); err != nil || h.ID != HouseholdMock || h.Role != "member" {
		t.Fatalf("bob joining MOCK1234: %+v %v", h, err)
	}
}
