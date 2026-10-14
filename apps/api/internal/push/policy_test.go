package push

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"
)

type fakeStore struct {
	mu      sync.Mutex
	tokens  map[string][]Token // hid -> tokens (uid encoded in the token as "<uid>:<n>")
	dropped []string
}

func (f *fakeStore) HouseholdPushTokens(_ context.Context, hid, excludeUID string) ([]Token, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []Token
	for _, t := range f.tokens[hid] {
		if t.Token[:len(excludeUID)] == excludeUID && t.Token[len(excludeUID)] == ':' {
			continue
		}
		out = append(out, t)
	}
	return out, nil
}
func (f *fakeStore) DropPushToken(_ context.Context, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.dropped = append(f.dropped, token)
	return nil
}
func (f *fakeStore) ActorName(_ context.Context, uid string) (string, error) {
	return map[string]string{"alice": "Alice", "bob": "Bob"}[uid], nil
}
func (f *fakeStore) HouseholdName(_ context.Context, hid string) (string, error) {
	return "Mock Household", nil
}

type fakeSender struct {
	mu   sync.Mutex
	sent []Message
	dead map[string]bool
}

func (f *fakeSender) Send(_ context.Context, m Message) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.dead[m.Token] {
		return ErrUnregistered
	}
	f.sent = append(f.sent, m)
	return nil
}
func (f *fakeSender) messages() []Message {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]Message(nil), f.sent...)
}

func newTestNotifier(t *testing.T) (*Notifier, *fakeStore, *fakeSender) {
	t.Helper()
	st := &fakeStore{tokens: map[string][]Token{"h1": {{Token: "alice:1", Platform: "ios"}, {Token: "bob:1", Platform: "android"}, {Token: "bob:2", Platform: "ios"}}}}
	snd := &fakeSender{dead: map[string]bool{}}
	n := NewNotifier(st, snd, slog.New(slog.NewTextHandler(io.Discard, nil)), 50*time.Millisecond)
	t.Cleanup(n.Close)
	return n, st, snd
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("condition not met in time")
}

func TestInsertNotifiesOthersOnly(t *testing.T) {
	n, _, snd := newTestNotifier(t)
	n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "insert", Row: map[string]any{"name": "Milk"}, Actor: "alice"})
	waitFor(t, func() bool { return len(snd.messages()) == 2 })
	for _, m := range snd.messages() {
		if m.Token[:4] != "bob:" {
			t.Fatalf("actor received a push: %+v", m)
		}
		if m.Title != "Mock Household" || m.Body != "Alice added Milk" || m.HouseholdID != "h1" || m.Type != "shopping_list_items.insert" {
			t.Fatalf("message: %+v", m)
		}
	}
}

func TestTogglesAndDeletesAreSilent(t *testing.T) {
	n, _, snd := newTestNotifier(t)
	n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "update", Row: map[string]any{"name": "Milk", "status": "bought"}, Actor: "alice"})
	n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "delete", Row: map[string]any{"id": "x"}, Actor: "alice"})
	n.Notify(Change{HouseholdID: "h1", Table: "shops", Type: "insert", Row: map[string]any{"name": "Lidl"}, Actor: "alice"})
	time.Sleep(150 * time.Millisecond)
	if got := snd.messages(); len(got) != 0 {
		t.Fatalf("want silence, got %+v", got)
	}
}

func TestBurstCollapses(t *testing.T) {
	n, _, snd := newTestNotifier(t)
	for _, name := range []string{"Milk", "Eggs", "Bread", "Butter", "Jam"} {
		n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "insert", Row: map[string]any{"name": name}, Actor: "alice"})
	}
	waitFor(t, func() bool { return len(snd.messages()) == 2 })
	time.Sleep(100 * time.Millisecond)
	got := snd.messages()
	if len(got) != 2 || got[0].Body != "Alice added 5 items" {
		t.Fatalf("want one collapsed push per recipient, got %+v", got)
	}
}

func TestJoinNotifies(t *testing.T) {
	n, _, snd := newTestNotifier(t)
	n.Notify(Change{HouseholdID: "h1", Table: "household_members", Type: "insert", Row: map[string]any{"user_id": "bob"}, Actor: "bob"})
	waitFor(t, func() bool { return len(snd.messages()) == 1 })
	m := snd.messages()[0]
	if m.Token != "alice:1" || m.Body != "Bob joined Mock Household" || m.Type != "household_members.insert" {
		t.Fatalf("message: %+v", m)
	}
}

func TestDeadTokenIsDropped(t *testing.T) {
	n, st, snd := newTestNotifier(t)
	snd.dead["bob:2"] = true
	n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "insert", Row: map[string]any{"name": "Milk"}, Actor: "alice"})
	waitFor(t, func() bool { st.mu.Lock(); defer st.mu.Unlock(); return len(st.dropped) == 1 })
	st.mu.Lock()
	defer st.mu.Unlock()
	if st.dropped[0] != "bob:2" {
		t.Fatalf("dropped %v", st.dropped)
	}
	if len(snd.messages()) != 1 {
		t.Fatalf("live token should still get the push: %+v", snd.messages())
	}
}

func TestCloseFlushesPending(t *testing.T) {
	st := &fakeStore{tokens: map[string][]Token{"h1": {{Token: "bob:1"}}}}
	snd := &fakeSender{}
	n := NewNotifier(st, snd, slog.New(slog.NewTextHandler(io.Discard, nil)), time.Hour)
	n.Notify(Change{HouseholdID: "h1", Table: "shopping_list_items", Type: "insert", Row: map[string]any{"name": "Milk"}, Actor: "alice"})
	time.Sleep(20 * time.Millisecond)
	n.Close()
	if got := snd.messages(); len(got) != 1 || got[0].Body != "Alice added Milk" {
		t.Fatalf("pending batch not flushed on close: %+v", got)
	}
}

var _ = errors.New
