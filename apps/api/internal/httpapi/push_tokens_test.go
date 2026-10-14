package httpapi

import (
	"context"
	"testing"
)

func TestPushTokens(t *testing.T) {
	e := newEnv(t)
	e.expect(200, "alice", "GET", "/v1/me", "", nil)
	e.expect(200, "bob", "GET", "/v1/me", "", nil)

	e.expect(400, "alice", "PUT", "/v1/me/push-tokens", `{"token":"","platform":"ios"}`, nil)
	e.expect(400, "alice", "PUT", "/v1/me/push-tokens", `{"token":"abc","platform":"web"}`, nil)
	e.expect(204, "alice", "PUT", "/v1/me/push-tokens", `{"token":"fcm-alice-1","platform":"ios"}`, nil)
	e.expect(204, "alice", "PUT", "/v1/me/push-tokens", `{"token":"fcm-alice-1","platform":"ios"}`, nil) // idempotent

	// The token moves to whoever registers it last (shared device, re-login as someone else).
	e.expect(204, "bob", "PUT", "/v1/me/push-tokens", `{"token":"fcm-alice-1","platform":"android"}`, nil)
	rows, err := e.db.HouseholdPushTokens(context.Background(), "none", "")
	if err != nil || len(rows) != 0 {
		t.Fatalf("no household: %v %v", rows, err)
	}

	// Membership scoping: alice's household sees bob's token only once bob is a member.
	var h struct {
		ID string `json:"id"`
	}
	e.expect(201, "alice", "POST", "/v1/households", `{"name":"Home"}`, &h)
	e.expect(204, "alice", "PUT", "/v1/me/push-tokens", `{"token":"fcm-alice-2","platform":"ios"}`, nil)
	if rows, _ = e.db.HouseholdPushTokens(context.Background(), h.ID, "alice"); len(rows) != 0 {
		t.Fatalf("bob is not a member yet: %+v", rows)
	}
	if rows, _ = e.db.HouseholdPushTokens(context.Background(), h.ID, "bob"); len(rows) != 1 || rows[0].Token != "fcm-alice-2" {
		t.Fatalf("alice's token: %+v", rows)
	}

	// Deleting someone else's token is a silent no-op; deleting your own works and is idempotent.
	e.expect(204, "alice", "DELETE", "/v1/me/push-tokens/fcm-alice-1", "", nil)
	if rows, _ = e.db.HouseholdPushTokens(context.Background(), h.ID, "alice"); len(rows) != 0 {
		t.Fatalf("bob's token should be untouched, but he is not a member: %+v", rows)
	}
	e.expect(204, "alice", "DELETE", "/v1/me/push-tokens/fcm-alice-2", "", nil)
	e.expect(204, "alice", "DELETE", "/v1/me/push-tokens/fcm-alice-2", "", nil)
	if rows, _ = e.db.HouseholdPushTokens(context.Background(), h.ID, "bob"); len(rows) != 0 {
		t.Fatalf("token should be gone: %+v", rows)
	}
	if res, _ := e.do("PUT", "/v1/me/push-tokens", `{"token":"x","platform":"ios"}`, map[string]string{"Authorization": "Bearer garbage"}); res.StatusCode != 401 {
		t.Fatalf("want 401, got %d", res.StatusCode)
	}
}

func TestPublishHookSeesCommittedChanges(t *testing.T) {
	e := newEnv(t)
	var h struct {
		ID string `json:"id"`
	}
	e.expect(201, "alice", "POST", "/v1/households", `{"name":"Home"}`, &h)
	e.expect(201, "alice", "POST", "/v1/households/"+h.ID+"/items", `{"name":"Milk"}`, nil)
	e.hooks.mu.Lock()
	defer e.hooks.mu.Unlock()
	var seen bool
	for _, c := range e.hooks.seen {
		if c.hid == h.ID && c.table == "shopping_list_items" && c.typ == "insert" && c.actor == "alice" {
			seen = true
		}
	}
	if !seen {
		t.Fatalf("OnPublish did not see the insert: %+v", e.hooks.seen)
	}
}
