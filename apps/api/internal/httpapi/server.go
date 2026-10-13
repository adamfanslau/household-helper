// Package httpapi is the HTTP surface of hh-api: /healthz, /readyz and the
// authenticated JSON API under /v1 (added in later steps).
package httpapi

import (
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/auth"
	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
	"golang.org/x/time/rate"
)

// Options wires a Server.
type Options struct {
	DB       *store.DB
	Log      *slog.Logger
	Verifier auth.Verifier
	Hub      *sse.Hub // nil = a private hub
	Version  string   // build SHA reported by /healthz
	Auth     string   // "firebase" or "emulator", reported by /healthz
	// RequestTimeout wraps the JSON routes in http.TimeoutHandler; 0 means 30s.
	// SSE is mounted outside it (TimeoutHandler has no Flusher).
	RequestTimeout time.Duration
	// Heartbeat is the SSE ping interval; 0 means 25s (Cloudflare idles at 100s).
	Heartbeat time.Duration
}

// Server holds the dependencies of every handler.
type Server struct {
	db        *store.DB
	log       *slog.Logger
	verifier  auth.Verifier
	hub       *sse.Hub
	version   string
	auth      string
	timeout   time.Duration
	heartbeat time.Duration

	seen  seen // uid -> last EnsureUser
	joins struct {
		mu sync.Mutex
		m  map[string]*rate.Limiter
	}
}

// New builds the full handler chain.
func New(o Options) http.Handler {
	if o.Log == nil {
		o.Log = slog.Default()
	}
	if o.RequestTimeout == 0 {
		o.RequestTimeout = 30 * time.Second
	}
	if o.Auth == "" {
		o.Auth = "firebase"
	}
	if o.Hub == nil {
		o.Hub = sse.New()
	}
	if o.Heartbeat == 0 {
		o.Heartbeat = 25 * time.Second
	}
	s := &Server{db: o.DB, log: o.Log, verifier: o.Verifier, hub: o.Hub, version: o.Version, auth: o.Auth, timeout: o.RequestTimeout, heartbeat: o.Heartbeat}
	s.seen.m = map[string]time.Time{}
	s.joins.m = map[string]*rate.Limiter{}
	return s.handler()
}

func (s *Server) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.healthz)
	mux.HandleFunc("GET /readyz", s.readyz)
	mux.HandleFunc("/", s.notFound)

	// The event stream must sit outside http.TimeoutHandler (no Flusher, and it
	// would cut the stream at 30 s). ServeMux prefers the more specific pattern.
	mux.Handle("GET /v1/households/{hid}/events", s.requireAuth(http.HandlerFunc(s.member(s.events))))

	v1 := http.NewServeMux()
	s.routes(v1)
	mux.Handle("/v1/", http.TimeoutHandler(s.requireAuth(v1), s.timeout, `{"error":{"code":"unavailable","message":"request timed out","fields":null}}`))

	var h http.Handler = mux
	h = maxBytes(h, 64<<10)
	h = noStore(h)
	h = s.accessLog(h)
	h = requestID(h)
	h = s.recoverer(h)
	return h
}

func (s *Server) notFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotFound, "not_found", "no such route", nil)
}
