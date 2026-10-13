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
	"testing"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

type env struct {
	t   *testing.T
	srv *httptest.Server
	db  *store.DB
}

func newEnv(t *testing.T) *env {
	t.Helper()
	db, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	h := New(Options{DB: db, Log: slog.New(slog.NewTextHandler(io.Discard, nil)), Version: "abc123", Auth: "emulator"})
	srv := httptest.NewServer(h)
	t.Cleanup(func() { srv.Close(); db.Close() })
	return &env{t: t, srv: srv, db: db}
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
