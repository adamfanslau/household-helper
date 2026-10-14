package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/adamfanslau/household-helper/apps/api/internal/auth"
	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// fakeVerifier maps "tok-<uid>" to a principal; anything else is invalid.
type fakeVerifier struct{}

func (fakeVerifier) Verify(_ context.Context, token string) (auth.Principal, error) {
	uid, ok := strings.CutPrefix(token, "tok-")
	if !ok || uid == "" {
		return auth.Principal{}, auth.ErrInvalidToken
	}
	return auth.Principal{UID: uid, Email: uid + "@test.com", Name: strings.ToUpper(uid[:1]) + uid[1:], Provider: "google.com"}, nil
}

type env struct {
	t     *testing.T
	srv   *httptest.Server
	db    *store.DB
	hooks *publishLog
}

// publishLog records what Options.OnPublish was handed (the push notifier's input).
type publishLog struct {
	mu   sync.Mutex
	seen []publishedChange
}

type publishedChange struct{ hid, table, typ, actor string }

func (p *publishLog) record(hid string, e sse.Event) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.seen = append(p.seen, publishedChange{hid, e.Table, e.Type, e.Actor})
}

func newEnv(t *testing.T) *env {
	t.Helper()
	db, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	hooks := &publishLog{}
	h := New(Options{DB: db, Log: slog.New(slog.NewTextHandler(io.Discard, nil)), Verifier: fakeVerifier{}, Version: "abc123", Auth: "emulator", OnPublish: hooks.record})
	srv := httptest.NewServer(h)
	t.Cleanup(func() { srv.Close(); db.Close() })
	return &env{t: t, srv: srv, db: db, hooks: hooks}
}

func (e *env) do(method, path string, body string, hdr map[string]string) (*http.Response, string) {
	e.t.Helper()
	req, err := http.NewRequest(method, e.srv.URL+path, strings.NewReader(body))
	if err != nil {
		e.t.Fatal(err)
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	return res, string(b)
}

// as performs a request as uid and decodes the JSON body into out (when non-nil).
func (e *env) as(uid, method, path, body string, out any) (int, string) {
	e.t.Helper()
	res, b := e.do(method, path, body, map[string]string{"Authorization": "Bearer tok-" + uid, "Content-Type": "application/json"})
	if out != nil && res.StatusCode < 300 {
		if err := json.Unmarshal([]byte(b), out); err != nil {
			e.t.Fatalf("%s %s: bad JSON %q: %v", method, path, b, err)
		}
	}
	return res.StatusCode, b
}

func (e *env) want(code int, got int, body string) {
	e.t.Helper()
	if got != code {
		e.t.Fatalf("want %d, got %d: %s", code, got, body)
	}
}

// expect is as + want in one call.
func (e *env) expect(code int, uid, method, path, body string, out any) string {
	e.t.Helper()
	got, b := e.as(uid, method, path, body, out)
	e.want(code, got, b)
	return b
}

func TestHealth(t *testing.T) {
	e := newEnv(t)
	res, body := e.do("GET", "/healthz", "", nil)
	if res.StatusCode != 200 {
		t.Fatalf("healthz %d %s", res.StatusCode, body)
	}
	var h healthBody
	if err := json.Unmarshal([]byte(body), &h); err != nil || h.Version != "abc123" || h.Auth != "emulator" {
		t.Fatalf("healthz body %q (%v)", body, err)
	}
	if !strings.Contains(body, "abc123") {
		t.Fatal("deploy-shell greps the SHA out of the health body")
	}
	if res.Header.Get("X-Request-Id") == "" {
		t.Fatal("missing X-Request-Id")
	}
	res, body = e.do("GET", "/readyz", "", nil)
	if res.StatusCode != 200 || body != "ok\n" {
		t.Fatalf("readyz %d %q", res.StatusCode, body)
	}
}

func TestRequestIDAndNotFound(t *testing.T) {
	e := newEnv(t)
	res, body := e.do("GET", "/nope", "", map[string]string{"X-Request-Id": "client-id-1"})
	if res.StatusCode != 404 || !strings.Contains(body, `"code":"not_found"`) {
		t.Fatalf("unknown route: %d %s", res.StatusCode, body)
	}
	if res.Header.Get("X-Request-Id") != "client-id-1" {
		t.Fatalf("request id not echoed: %q", res.Header.Get("X-Request-Id"))
	}
	res, _ = e.do("GET", "/nope", "", map[string]string{"X-Request-Id": "bad id"})
	if id := res.Header.Get("X-Request-Id"); id == "" || strings.Contains(id, " ") {
		t.Fatalf("malformed client id must be replaced, got %q", id)
	}
}

func TestAuthRequired(t *testing.T) {
	e := newEnv(t)
	res, body := e.do("GET", "/v1/me", "", nil)
	if res.StatusCode != 401 || !strings.Contains(body, "unauthorized") {
		t.Fatalf("no token: %d %s", res.StatusCode, body)
	}
	res, _ = e.do("GET", "/v1/me", "", map[string]string{"Authorization": "Bearer garbage"})
	if res.StatusCode != 401 {
		t.Fatalf("garbage token: %d", res.StatusCode)
	}
	res, _ = e.do("GET", "/v1/me", "", map[string]string{"Authorization": "Basic tok-a"})
	if res.StatusCode != 401 {
		t.Fatalf("non-bearer: %d", res.StatusCode)
	}
	if res.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("/v1 responses must be no-store")
	}
}

func TestMe(t *testing.T) {
	e := newEnv(t)
	var u store.User
	e.expect(200, "a", "GET", "/v1/me", "", &u)
	if u.ID != "a" || u.Email != "a@test.com" || u.DisplayName != "A" || u.Provider != "google.com" {
		t.Fatalf("me: %+v", u)
	}
}

// TestHouseholdAuthz ports supabase/tests/rls_smoke_test.sql: A creates, C is an
// outsider, B joins by code, bogus codes fail.
func TestHouseholdAuthz(t *testing.T) {
	e := newEnv(t)

	var h store.Household
	code, body := e.as("a", "POST", "/v1/households", `{"name":"Test Home"}`, &h)
	e.want(201, code, body)
	if h.Name != "Test Home" || h.Role != "owner" || h.CreatedBy == nil || *h.CreatedBy != "a" {
		t.Fatalf("created: %+v", h)
	}
	code, body = e.as("a", "POST", "/v1/households", `{"name":""}`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "POST", "/v1/households", `{"name":"`+strings.Repeat("x", 101)+`"}`, nil)
	e.want(400, code, body)

	var list []store.Household
	e.expect(200, "a", "GET", "/v1/households", "", &list)
	if len(list) != 1 || list[0].ID != h.ID {
		t.Fatalf("a sees %+v", list)
	}

	// The first invite was minted server-side with the household.
	var invites []store.Invite
	e.expect(200, "a", "GET", "/v1/households/"+h.ID+"/invites", "", &invites)
	if len(invites) != 1 || len(invites[0].Code) != 8 || invites[0].RevokedAt != nil {
		t.Fatalf("invites: %+v", invites)
	}
	inviteCode := invites[0].Code

	// C is an outsider: empty list, 404 on everything household-scoped.
	e.expect(200, "c", "GET", "/v1/households", "", &list)
	if len(list) != 0 {
		t.Fatalf("c sees %+v", list)
	}
	code, body = e.as("c", "GET", "/v1/households/"+h.ID, "", nil)
	e.want(404, code, body)
	code, body = e.as("c", "GET", "/v1/households/"+h.ID+"/invites", "", nil)
	e.want(404, code, body)
	code, body = e.as("c", "PATCH", "/v1/households/"+h.ID, `{"name":"Hacked"}`, nil)
	e.want(404, code, body)
	code, body = e.as("c", "POST", "/v1/households/"+h.ID+"/invites", "", nil)
	e.want(404, code, body)

	// B joins with the code (lower-case and padded: the server normalises) and gets the household back.
	var joined store.Household
	code, body = e.as("b", "POST", "/v1/households/join", `{"code":" `+strings.ToLower(inviteCode)+` "}`, &joined)
	e.want(200, code, body)
	if joined.ID != h.ID || joined.Role != "member" {
		t.Fatalf("joined: %+v", joined)
	}
	e.expect(200, "b", "GET", "/v1/households", "", &list)
	if len(list) != 1 || list[0].Role != "member" {
		t.Fatalf("b sees %+v", list)
	}
	// Joining twice is idempotent.
	code, body = e.as("b", "POST", "/v1/households/join", `{"code":"`+inviteCode+`"}`, &joined)
	e.want(200, code, body)

	// Bogus and malformed codes.
	code, body = e.as("c", "POST", "/v1/households/join", `{"code":"BOGUS123"}`, nil)
	e.want(404, code, body)
	if !strings.Contains(body, "invalid or expired invite code") {
		t.Fatalf("bogus body: %s", body)
	}
	code, body = e.as("c", "POST", "/v1/households/join", `{"code":"short"}`, nil)
	e.want(400, code, body)

	// Members can rename; the change is visible to the other member.
	var renamed store.Household
	code, body = e.as("b", "PATCH", "/v1/households/"+h.ID, `{"name":"Our Home"}`, &renamed)
	e.want(200, code, body)
	e.expect(200, "a", "GET", "/v1/households/"+h.ID, "", &renamed)
	if renamed.Name != "Our Home" || renamed.Role != "owner" {
		t.Fatalf("renamed: %+v", renamed)
	}

	// New invite, revoke the old one: the revoked code no longer joins.
	var inv store.Invite
	code, body = e.as("a", "POST", "/v1/households/"+h.ID+"/invites", "", &inv)
	e.want(201, code, body)
	code, body = e.as("a", "POST", "/v1/households/"+h.ID+"/invites/"+invites[0].ID+"/revoke", "", &inv)
	e.want(200, code, body)
	if inv.RevokedAt == nil {
		t.Fatalf("revoke: %+v", inv)
	}
	code, body = e.as("c", "POST", "/v1/households/join", `{"code":"`+inviteCode+`"}`, nil)
	e.want(404, code, body)
	// Revoking across households is a 404 even for a member of another household.
	var other store.Household
	e.expect(201, "c", "POST", "/v1/households", `{"name":"C Home"}`, &other)
	code, body = e.as("c", "POST", "/v1/households/"+other.ID+"/invites/"+inv.ID+"/revoke", "", nil)
	e.want(404, code, body)
}

func TestJoinRateLimit(t *testing.T) {
	e := newEnv(t)
	var got429 bool
	for i := 0; i < 15; i++ {
		code, _ := e.as("z", "POST", "/v1/households/join", `{"code":"BOGUS123"}`, nil)
		if code == 429 {
			got429 = true
			break
		}
	}
	if !got429 {
		t.Fatal("expected 429 after a burst of join attempts")
	}
	// Other users are unaffected.
	code, _ := e.as("y", "POST", "/v1/households/join", `{"code":"BOGUS123"}`, nil)
	if code != 404 {
		t.Fatalf("other user limited: %d", code)
	}
}

func TestBodyLimitAndMalformedJSON(t *testing.T) {
	e := newEnv(t)
	code, body := e.as("a", "POST", "/v1/households", `{"name":`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "POST", "/v1/households", `{"name":"`+strings.Repeat("x", 70<<10)+`"}`, nil)
	e.want(413, code, body)
}
