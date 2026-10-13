package httpapi

import (
	"context"
	"net/http"
	"time"
)

type healthBody struct {
	Version string `json:"version"`
	Auth    string `json:"auth"`
	DB      string `json:"db,omitempty"`
}

// healthz is what deploy-shell and the deploy workflow poll: the body must contain
// the build SHA (vps/docs/25-apps.md). It also tells which verifier is live.
func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, healthBody{Version: s.version, Auth: s.auth, DB: "not ready"})
		return
	}
	writeJSON(w, http.StatusOK, healthBody{Version: s.version, Auth: s.auth})
}

func (s *Server) readyz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Ping(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte("not ready\n"))
		return
	}
	_, _ = w.Write([]byte("ok\n"))
}
