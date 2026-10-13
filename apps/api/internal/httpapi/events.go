package httpapi

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
)

// events streams the household's changes as Server-Sent Events. It is mounted
// outside http.TimeoutHandler (which has no Flusher) and the server has no
// WriteTimeout; the stream ends at the token's expiry, on disconnect, or when the
// hub drops a slow subscriber. Frames:
//
//	event: ready        data: {"household_id": "..."}   (sent first; clients refetch on it)
//	event: change       id: <event id>  data: sse.Event
//	: ping              every heartbeat (25 s; Cloudflare idles at 100 s)
func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	hid := r.PathValue("hid")
	p := principal(r)
	rc := http.NewResponseController(w)
	_ = rc.SetWriteDeadline(time.Time{})

	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	ch, cancel := s.hub.Subscribe(hid)
	defer cancel()

	ready, _ := json.Marshal(map[string]string{"household_id": hid})
	if _, err := w.Write([]byte("event: ready\ndata: " + string(ready) + "\n\n")); err != nil {
		return
	}
	if err := rc.Flush(); err != nil {
		return
	}

	deadline := p.Expiry
	if deadline.IsZero() || time.Until(deadline) > time.Hour {
		deadline = time.Now().Add(time.Hour)
	}
	expiry := time.NewTimer(time.Until(deadline))
	defer expiry.Stop()
	ping := time.NewTicker(s.heartbeat)
	defer ping.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case <-expiry.C:
			return // the client reconnects with a fresh token
		case <-ping.C:
			if _, err := w.Write([]byte(": ping\n\n")); err != nil {
				return
			}
			if err := rc.Flush(); err != nil {
				return
			}
		case e, ok := <-ch:
			if !ok {
				return // dropped as a slow subscriber; the client reconnects and refetches
			}
			data, err := json.Marshal(e)
			if err != nil {
				s.log.Error("sse marshal", "err", err.Error())
				continue
			}
			if _, err := w.Write([]byte("id: " + e.ID + "\nevent: change\ndata: " + string(data) + "\n\n")); err != nil {
				return
			}
			if err := rc.Flush(); err != nil {
				return
			}
		}
	}
}

// publish fans out one committed change to the household's streams.
func (s *Server) publish(r *http.Request, table, typ string, row any) {
	s.hub.Publish(r.PathValue("hid"), sse.Event{ID: ids.New(), Table: table, Type: typ, Row: row, Actor: principal(r).UID})
}

// publishTo is publish for routes without {hid} in the path (join).
func (s *Server) publishTo(r *http.Request, hid, table, typ string, row any) {
	s.hub.Publish(hid, sse.Event{ID: ids.New(), Table: table, Type: typ, Row: row, Actor: principal(r).UID})
}

type idRow struct {
	ID string `json:"id"`
}

type catalogDeleteRow struct {
	ID     string `json:"id"`
	ShopID string `json:"shop_id"`
}
