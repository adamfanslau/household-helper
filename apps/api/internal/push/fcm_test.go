package push

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

// testServiceAccount returns a fake key file whose token_uri points at tokenURL.
func testServiceAccount(t *testing.T, tokenURL string) *ServiceAccount {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, _ := x509.MarshalPKCS8PrivateKey(key)
	pemKey := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	raw, _ := json.Marshal(map[string]string{"client_email": "hh-api-fcm@test.iam.gserviceaccount.com", "private_key": pemKey, "token_uri": tokenURL, "project_id": "test-project"}) // secrets-check: allow (key generated per test run)
	sa, err := ParseServiceAccount(raw)
	if err != nil {
		t.Fatal(err)
	}
	return sa
}

// fakeGoogle serves the token endpoint and the FCM send endpoint.
type fakeGoogle struct {
	tokenCalls atomic.Int32
	sendCalls  atomic.Int32
	lastBody   atomic.Value // map[string]any
	status     atomic.Int32 // 0 = 200
	errorJSON  string
}

func (f *fakeGoogle) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		f.tokenCalls.Add(1)
		if r.FormValue("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.FormValue("assertion") == "" {
			http.Error(w, "bad grant", 400)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"access_token":"ya29.test","expires_in":3600,"token_type":"Bearer"}`)
	})
	mux.HandleFunc("POST /v1/projects/test-project/messages:send", func(w http.ResponseWriter, r *http.Request) {
		f.sendCalls.Add(1)
		if r.Header.Get("Authorization") != "Bearer ya29.test" {
			http.Error(w, "no auth", 401)
			return
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		f.lastBody.Store(body)
		if st := f.status.Load(); st != 0 {
			w.WriteHeader(int(st))
			_, _ = io.WriteString(w, f.errorJSON)
			return
		}
		_, _ = io.WriteString(w, `{"name":"projects/test-project/messages/1"}`)
	})
	return mux
}

func newTestClient(t *testing.T) (*Client, *fakeGoogle) {
	t.Helper()
	f := &fakeGoogle{}
	srv := httptest.NewServer(f.handler())
	t.Cleanup(srv.Close)
	sa := testServiceAccount(t, srv.URL+"/token")
	c := NewClient("test-project", NewTokenSource(sa, srv.Client()), srv.Client()).WithEndpoint(srv.URL + "/v1/projects/test-project/messages:send")
	return c, f
}

func TestSendBodyShapeAndTokenCache(t *testing.T) {
	c, f := newTestClient(t)
	m := Message{Token: "tok-1", Title: "Mock Household", Body: "Alice added Milk", HouseholdID: "h1", Type: "shopping_list_items.insert"}
	for i := 0; i < 2; i++ {
		if err := c.Send(context.Background(), m); err != nil {
			t.Fatal(err)
		}
	}
	if f.tokenCalls.Load() != 1 {
		t.Fatalf("access token should be cached, got %d token requests", f.tokenCalls.Load())
	}
	body := f.lastBody.Load().(map[string]any)
	msg := body["message"].(map[string]any)
	if msg["token"] != "tok-1" {
		t.Fatalf("token: %v", msg["token"])
	}
	n := msg["notification"].(map[string]any)
	if n["title"] != "Mock Household" || n["body"] != "Alice added Milk" {
		t.Fatalf("notification: %v", n)
	}
	d := msg["data"].(map[string]any)
	if d["household_id"] != "h1" || d["type"] != "shopping_list_items.insert" {
		t.Fatalf("data: %v", d)
	}
	android := msg["android"].(map[string]any)
	if android["collapse_key"] != "hh-h1" || android["priority"] != "high" || android["notification"].(map[string]any)["channel_id"] != "household" {
		t.Fatalf("android: %v", android)
	}
	apns := msg["apns"].(map[string]any)
	if apns["headers"].(map[string]any)["apns-collapse-id"] != "hh-h1" {
		t.Fatalf("apns headers: %v", apns["headers"])
	}
	aps := apns["payload"].(map[string]any)["aps"].(map[string]any)
	if aps["thread-id"] != "h1" || aps["sound"] != "default" {
		t.Fatalf("aps: %v", aps)
	}
}

func TestSendErrors(t *testing.T) {
	cases := []struct {
		status       int
		body         string
		unregistered bool
	}{
		{404, `{"error":{"code":404,"status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`, true},
		{400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","details":[{"errorCode":"INVALID_ARGUMENT"}]}}`, true},
		{403, `{"error":{"code":403,"status":"PERMISSION_DENIED","details":[{"errorCode":"SENDER_ID_MISMATCH"}]}}`, true},
		{429, `{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"errorCode":"QUOTA_EXCEEDED"}]}}`, false},
		{503, `{"error":{"code":503,"status":"UNAVAILABLE"}}`, false},
	}
	for _, tc := range cases {
		c, f := newTestClient(t)
		f.status.Store(int32(tc.status))
		f.errorJSON = tc.body
		err := c.Send(context.Background(), Message{Token: "t", HouseholdID: "h"})
		if err == nil {
			t.Fatalf("HTTP %d: want error", tc.status)
		}
		if got := strings.Contains(err.Error(), ErrUnregistered.Error()); got != tc.unregistered {
			t.Fatalf("HTTP %d: unregistered=%v, err=%v", tc.status, got, err)
		}
	}
}

func TestParseServiceAccountRejectsGarbage(t *testing.T) {
	if _, err := ParseServiceAccount([]byte(`{"client_email":"a@b","private_key":"not pem"}`)); err == nil { // secrets-check: allow (garbage input)
		t.Fatal("want error for a non-PEM key")
	}
	if _, err := ParseServiceAccount([]byte(`{}`)); err == nil {
		t.Fatal("want error for missing fields")
	}
}
