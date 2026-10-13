// Package sse is the in-process fan-out behind GET /v1/households/{hid}/events.
// One process serves all connections, so a plain map of channels is enough; the
// Litestream/SQLite single-writer setup already rules out a second API process.
package sse

import (
	"sync"
)

// Event is one change frame: data is this struct as JSON. Row is the full row for
// insert/update and {"id": ...} (plus the parent id where useful) for delete.
type Event struct {
	ID    string `json:"id"`    // UUIDv7, also sent as the SSE id:
	Table string `json:"table"` // shopping_list_items | shops | catalog_items | households | household_members | household_invites
	Type  string `json:"type"`  // insert | update | delete
	Row   any    `json:"row"`
	Actor string `json:"actor"` // uid of the caller that made the change
}

const bufferSize = 64

type Hub struct {
	mu   sync.Mutex
	subs map[string]map[chan Event]struct{} // household id -> subscribers
}

func New() *Hub {
	return &Hub{subs: map[string]map[chan Event]struct{}{}}
}

// Subscribe returns a buffered channel of the household's events and a cancel
// func. The channel is closed when the hub drops the subscriber for being slow
// (buffer full); the handler then ends the stream and the client reconnects + refetches.
func (h *Hub) Subscribe(hid string) (<-chan Event, func()) {
	ch := make(chan Event, bufferSize)
	h.mu.Lock()
	if h.subs[hid] == nil {
		h.subs[hid] = map[chan Event]struct{}{}
	}
	h.subs[hid][ch] = struct{}{}
	h.mu.Unlock()
	var once sync.Once
	cancel := func() {
		once.Do(func() {
			h.mu.Lock()
			if set, ok := h.subs[hid]; ok {
				if _, live := set[ch]; live {
					delete(set, ch)
					close(ch)
				}
				if len(set) == 0 {
					delete(h.subs, hid)
				}
			}
			h.mu.Unlock()
		})
	}
	return ch, cancel
}

// Publish delivers e to every subscriber of hid without blocking. Call it only
// after the database transaction has committed.
func (h *Hub) Publish(hid string, e Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.subs[hid] {
		select {
		case ch <- e:
		default: // slow subscriber: drop it
			delete(h.subs[hid], ch)
			close(ch)
		}
	}
	if len(h.subs[hid]) == 0 {
		delete(h.subs, hid)
	}
}

// Subscribers reports the live subscriber count for hid (tests, diagnostics).
func (h *Hub) Subscribers(hid string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.subs[hid])
}
