package push

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"
)

// Store is what the policy needs from the database.
type Store interface {
	HouseholdPushTokens(ctx context.Context, hid, excludeUID string) ([]Token, error)
	DropPushToken(ctx context.Context, token string) error
	ActorName(ctx context.Context, uid string) (string, error)
	HouseholdName(ctx context.Context, hid string) (string, error)
}

// Token is one registered device.
type Token struct {
	Token    string
	Platform string
}

// Change is the committed change handed over by the API after publish.
type Change struct {
	HouseholdID string
	Table       string // shopping_list_items | household_members | ...
	Type        string // insert | update | delete
	Row         any
	Actor       string // uid
}

// Notifier turns changes into notifications: only list-item inserts ("Alice added
// Milk", bursts collapsed to "Alice added 3 items" per 5 s) and joins ("Bob joined
// Mock Household"). Recipients are the household's members minus the actor. One
// worker goroutine, a bounded queue, no retries: a missed push is not a lost change.
type Notifier struct {
	store    Store
	sender   Sender
	log      *slog.Logger
	debounce time.Duration
	queue    chan Change
	flush    chan string

	mu      sync.Mutex
	batches map[string]*batch // hid|actor -> pending item names
	wg      sync.WaitGroup
	stop    chan struct{}
	once    sync.Once
}

type batch struct {
	hid, actor string
	names      []string
	timer      *time.Timer
}

func NewNotifier(store Store, sender Sender, log *slog.Logger, debounce time.Duration) *Notifier {
	if log == nil {
		log = slog.Default()
	}
	if debounce <= 0 {
		debounce = 5 * time.Second
	}
	n := &Notifier{store: store, sender: sender, log: log, debounce: debounce,
		queue: make(chan Change, 64), flush: make(chan string, 64), batches: map[string]*batch{}, stop: make(chan struct{})}
	n.wg.Add(1)
	go n.run()
	return n
}

// Notify enqueues a change; it never blocks the request path (full queue = dropped + logged).
func (n *Notifier) Notify(c Change) {
	if !interesting(c) {
		return
	}
	select {
	case n.queue <- c:
	default:
		n.log.Warn("push: queue full, dropping", "household", c.HouseholdID, "table", c.Table)
	}
}

// Close flushes pending batches and stops the worker.
func (n *Notifier) Close() {
	n.once.Do(func() { close(n.stop) })
	n.wg.Wait()
}

func interesting(c Change) bool {
	return c.Type == "insert" && (c.Table == "shopping_list_items" || c.Table == "household_members")
}

func (n *Notifier) run() {
	defer n.wg.Done()
	for {
		select {
		case c := <-n.queue:
			n.handle(c)
		case key := <-n.flush:
			n.mu.Lock()
			b := n.batches[key]
			delete(n.batches, key)
			n.mu.Unlock()
			if b != nil {
				n.sendItems(b)
			}
		case <-n.stop:
			n.mu.Lock()
			pending := n.batches
			n.batches = map[string]*batch{}
			n.mu.Unlock()
			for _, b := range pending {
				b.timer.Stop()
				n.sendItems(b)
			}
			return
		}
	}
}

func (n *Notifier) handle(c Change) {
	switch c.Table {
	case "shopping_list_items":
		name := rowName(c.Row)
		key := c.HouseholdID + "|" + c.Actor
		n.mu.Lock()
		b := n.batches[key]
		if b == nil {
			b = &batch{hid: c.HouseholdID, actor: c.Actor}
			b.timer = time.AfterFunc(n.debounce, func() {
				select {
				case n.flush <- key:
				case <-n.stop:
				}
			})
			n.batches[key] = b
		}
		b.names = append(b.names, name)
		n.mu.Unlock()
	case "household_members":
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		actor, household := n.names(ctx, c.Actor, c.HouseholdID)
		n.deliver(ctx, c.HouseholdID, c.Actor, household, actor+" joined "+household, "household_members.insert")
	}
}

func (n *Notifier) sendItems(b *batch) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	actor, household := n.names(ctx, b.actor, b.hid)
	var body string
	if len(b.names) == 1 {
		body = actor + " added " + b.names[0]
	} else {
		body = fmt.Sprintf("%s added %d items", actor, len(b.names))
	}
	n.deliver(ctx, b.hid, b.actor, household, body, "shopping_list_items.insert")
}

func (n *Notifier) names(ctx context.Context, uid, hid string) (actor, household string) {
	actor, err := n.store.ActorName(ctx, uid)
	if err != nil || actor == "" {
		actor = "Someone"
	}
	household, err = n.store.HouseholdName(ctx, hid)
	if err != nil || household == "" {
		household = "Household Helper"
	}
	return actor, household
}

func (n *Notifier) deliver(ctx context.Context, hid, actor, title, body, typ string) {
	tokens, err := n.store.HouseholdPushTokens(ctx, hid, actor)
	if err != nil {
		n.log.Error("push: tokens", "err", err.Error())
		return
	}
	sent := 0
	for _, t := range tokens {
		err := n.sender.Send(ctx, Message{Token: t.Token, Title: title, Body: body, HouseholdID: hid, Type: typ})
		switch {
		case err == nil:
			sent++
		case errors.Is(err, ErrUnregistered):
			if derr := n.store.DropPushToken(ctx, t.Token); derr != nil {
				n.log.Error("push: drop token", "err", derr.Error())
			}
			n.log.Info("push: dropped dead token", "platform", t.Platform)
		default:
			n.log.Warn("push: send failed", "platform", t.Platform, "err", err.Error())
		}
	}
	n.log.Info("push: sent", "household", hid, "type", typ, "recipients", len(tokens), "delivered", sent)
}

// rowName reads "name" from whatever row type the API published.
func rowName(row any) string {
	b, err := json.Marshal(row)
	if err != nil {
		return "an item"
	}
	var r struct {
		Name string `json:"name"`
	}
	if json.Unmarshal(b, &r) != nil || strings.TrimSpace(r.Name) == "" {
		return "an item"
	}
	return r.Name
}
