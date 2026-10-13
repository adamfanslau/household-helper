package sse

import (
	"testing"
	"time"
)

func TestSubscribePublishCancel(t *testing.T) {
	h := New()
	a, cancelA := h.Subscribe("h1")
	b, cancelB := h.Subscribe("h1")
	other, cancelO := h.Subscribe("h2")
	defer cancelO()
	h.Publish("h1", Event{ID: "e1", Table: "shops", Type: "insert", Row: map[string]any{"id": "s1"}, Actor: "u1"})
	for _, ch := range []<-chan Event{a, b} {
		select {
		case e := <-ch:
			if e.ID != "e1" || e.Table != "shops" {
				t.Fatalf("got %+v", e)
			}
		case <-time.After(time.Second):
			t.Fatal("subscriber did not receive the event")
		}
	}
	select {
	case e := <-other:
		t.Fatalf("other household received %+v", e)
	default:
	}
	cancelA()
	cancelA() // idempotent
	if h.Subscribers("h1") != 1 {
		t.Fatalf("subscribers after cancel: %d", h.Subscribers("h1"))
	}
	if _, ok := <-a; ok {
		t.Fatal("cancelled channel should be closed")
	}
	cancelB()
	if h.Subscribers("h1") != 0 {
		t.Fatal("map entry should be gone")
	}
	h.Publish("h1", Event{ID: "e2"}) // no subscribers: no panic
}

func TestSlowSubscriberIsDropped(t *testing.T) {
	h := New()
	slow, cancel := h.Subscribe("h1")
	defer cancel()
	for i := 0; i <= bufferSize; i++ {
		h.Publish("h1", Event{ID: "e"})
	}
	if h.Subscribers("h1") != 0 {
		t.Fatal("slow subscriber should have been dropped")
	}
	n := 0
	for range slow {
		n++
	}
	if n != bufferSize {
		t.Fatalf("drained %d events, want %d then close", n, bufferSize)
	}
}
