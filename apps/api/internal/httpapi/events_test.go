package httpapi

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/auth"
	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// expiringVerifier is fakeVerifier with a short token life for "short-*" uids.
type expiringVerifier struct{}

func (expiringVerifier) Verify(ctx context.Context, token string) (auth.Principal, error) {
	p, err := fakeVerifier{}.Verify(ctx, token)
	if err != nil {
		return p, err
	}
	if strings.HasPrefix(p.UID, "short") {
		p.Expiry = time.Now().Add(300 * time.Millisecond)
	} else {
		p.Expiry = time.Now().Add(time.Hour)
	}
	return p, nil
}

func newSSEEnv(t *testing.T) *env {
	t.Helper()
	db, err := store.Open(context.Background(), filepath.Join(t.TempDir(), "api.db"))
	if err != nil {
		t.Fatal(err)
	}
	h := New(Options{DB: db, Log: slog.New(slog.NewTextHandler(io.Discard, nil)), Verifier: expiringVerifier{}, Version: "abc123", Heartbeat: 80 * time.Millisecond})
	srv := httptest.NewServer(h)
	t.Cleanup(func() { srv.Close(); db.Close() })
	return &env{t: t, srv: srv, db: db}
}

// frame is one parsed SSE block.
type frame struct {
	Event, ID, Data string
	Comment         bool
}

// readFrames parses blank-line separated SSE blocks from the stream into ch.
func readFrames(t *testing.T, body io.Reader, ch chan<- frame) {
	t.Helper()
	sc := bufio.NewScanner(body)
	var f frame
	flush := func() {
		if f.Event != "" || f.Data != "" || f.Comment {
			ch <- f
		}
		f = frame{}
	}
	for sc.Scan() {
		line := sc.Text()
		switch {
		case line == "":
			flush()
		case strings.HasPrefix(line, ":"):
			f.Comment = true
		case strings.HasPrefix(line, "event: "):
			f.Event = strings.TrimPrefix(line, "event: ")
		case strings.HasPrefix(line, "id: "):
			f.ID = strings.TrimPrefix(line, "id: ")
		case strings.HasPrefix(line, "data: "):
			f.Data += strings.TrimPrefix(line, "data: ")
		}
	}
	flush()
	close(ch)
}

func (e *env) stream(uid, hid string) (*http.Response, <-chan frame) {
	e.t.Helper()
	req, _ := http.NewRequest("GET", e.srv.URL+"/v1/households/"+hid+"/events", nil)
	req.Header.Set("Authorization", "Bearer tok-"+uid)
	res, err := (&http.Client{}).Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	ch := make(chan frame, 64)
	go readFrames(e.t, res.Body, ch)
	return res, ch
}

func next(t *testing.T, ch <-chan frame, want string) frame {
	t.Helper()
	deadline := time.After(3 * time.Second)
	for {
		select {
		case f, ok := <-ch:
			if !ok {
				t.Fatalf("stream closed while waiting for %q", want)
			}
			if want == "ping" && f.Comment {
				return f
			}
			if f.Event == want {
				return f
			}
			// ignore other frames (pings while waiting for a change, etc.)
		case <-deadline:
			t.Fatalf("timeout waiting for %q", want)
		}
	}
}

func TestEventsStream(t *testing.T) {
	e := newSSEEnv(t)
	var h store.Household
	e.expect(201, "a", "POST", "/v1/households", `{"name":"Home"}`, &h)
	var invites []store.Invite
	e.expect(200, "a", "GET", "/v1/households/"+h.ID+"/invites", "", &invites)
	e.expect(200, "b", "POST", "/v1/households/join", `{"code":"`+invites[0].Code+`"}`, nil)

	// Outsiders and anonymous callers never get a stream.
	res, body := e.do("GET", "/v1/households/"+h.ID+"/events", "", map[string]string{"Authorization": "Bearer tok-c"})
	if res.StatusCode != 404 {
		t.Fatalf("outsider: %d %s", res.StatusCode, body)
	}
	res, _ = e.do("GET", "/v1/households/"+h.ID+"/events", "", nil)
	if res.StatusCode != 401 {
		t.Fatalf("anonymous: %d", res.StatusCode)
	}

	res, frames := e.stream("a", h.ID)
	defer res.Body.Close()
	if ct := res.Header.Get("Content-Type"); res.StatusCode != 200 || ct != "text/event-stream" {
		t.Fatalf("stream: %d %q", res.StatusCode, ct)
	}
	ready := next(t, frames, "ready")
	if !strings.Contains(ready.Data, h.ID) {
		t.Fatalf("ready data %q", ready.Data)
	}
	next(t, frames, "ping") // heartbeat arrives on its own

	// A change by B is delivered to A's stream after commit, with the actor.
	var item store.ListItem
	e.expect(201, "b", "POST", "/v1/households/"+h.ID+"/items", `{"name":"Coffee"}`, &item)
	f := next(t, frames, "change")
	var ev sse.Event
	if err := json.Unmarshal([]byte(f.Data), &ev); err != nil {
		t.Fatalf("change data %q: %v", f.Data, err)
	}
	if ev.Table != "shopping_list_items" || ev.Type != "insert" || ev.Actor != "b" || f.ID != ev.ID || ev.ID == "" {
		t.Fatalf("event %+v (sse id %q)", ev, f.ID)
	}
	row, _ := ev.Row.(map[string]any)
	if row["id"] != item.ID || row["name"] != "Coffee" {
		t.Fatalf("row %+v", row)
	}

	// Updates and deletes follow; a delete carries only the id.
	e.expect(200, "a", "PATCH", "/v1/households/"+h.ID+"/items/"+item.ID, `{"status":"bought"}`, nil)
	f = next(t, frames, "change")
	_ = json.Unmarshal([]byte(f.Data), &ev)
	if ev.Type != "update" || ev.Actor != "a" {
		t.Fatalf("update event %+v", ev)
	}
	code, body := e.as("a", "DELETE", "/v1/households/"+h.ID+"/items?status=bought", "", nil)
	e.want(204, code, body)
	f = next(t, frames, "change")
	_ = json.Unmarshal([]byte(f.Data), &ev)
	row, _ = ev.Row.(map[string]any)
	if ev.Type != "delete" || row["id"] != item.ID || len(row) != 1 {
		t.Fatalf("delete event %+v", ev)
	}

	// Another household's changes are not delivered.
	var other store.Household
	e.expect(201, "c", "POST", "/v1/households", `{"name":"C"}`, &other)
	e.expect(201, "c", "POST", "/v1/households/"+other.ID+"/items", `{"name":"Secret"}`, nil)
	e.expect(201, "a", "POST", "/v1/households/"+h.ID+"/shops", `{"name":"Lidl"}`, nil)
	f = next(t, frames, "change")
	_ = json.Unmarshal([]byte(f.Data), &ev)
	if ev.Table != "shops" {
		t.Fatalf("expected the shop insert next, got %+v", ev)
	}
}

func TestEventsCloseAtTokenExpiry(t *testing.T) {
	e := newSSEEnv(t)
	var h store.Household
	e.expect(201, "short-a", "POST", "/v1/households", `{"name":"Home"}`, &h)
	res, frames := e.stream("short-a", h.ID)
	defer res.Body.Close()
	next(t, frames, "ready")
	start := time.Now()
	for range frames { // drains until the server closes the stream
	}
	if d := time.Since(start); d > 2*time.Second {
		t.Fatalf("stream should close at token expiry (~300ms), took %v", d)
	}
}
