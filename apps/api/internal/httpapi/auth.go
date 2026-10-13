package httpapi

import (
	"net/http"
	"sync"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/auth"
)

// requireAuth verifies the bearer token, upserts the user (throttled) and stores the Principal.
func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok, ok := auth.BearerToken(r.Header.Get("Authorization"))
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized", "missing bearer token", nil)
			return
		}
		p, err := s.verifier.Verify(r.Context(), tok)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "invalid or expired token", nil)
			return
		}
		if s.shouldEnsure(p.UID) {
			if err := s.db.EnsureUser(r.Context(), p.UID, p.Email, p.Name, p.Provider); err != nil {
				s.log.Error("ensure user", "err", err.Error())
				writeError(w, http.StatusInternalServerError, "internal", "could not record user", nil)
				return
			}
		}
		if info, ok := r.Context().Value(ctxReqInfo).(*reqInfo); ok {
			info.uid = p.UID
		}
		next.ServeHTTP(w, r.WithContext(auth.WithPrincipal(r.Context(), p)))
	})
}

type seen struct {
	mu sync.Mutex
	m  map[string]time.Time
}

func (s *Server) shouldEnsure(uid string) bool {
	s.seen.mu.Lock()
	defer s.seen.mu.Unlock()
	now := time.Now()
	if t, ok := s.seen.m[uid]; ok && now.Sub(t) < 15*time.Minute {
		return false
	}
	if len(s.seen.m) > 10000 {
		s.seen.m = map[string]time.Time{}
	}
	s.seen.m[uid] = now
	return true
}

// principal returns the verified caller; requireAuth guarantees it is set under /v1.
func principal(r *http.Request) auth.Principal {
	p, _ := auth.FromContext(r.Context())
	return p
}

// member wraps a household-scoped handler: the caller must be a member of {hid},
// otherwise 404 (non-members cannot tell whether the household exists).
func (s *Server) member(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		hid := r.PathValue("hid")
		ok, err := s.db.IsMember(r.Context(), hid, principal(r).UID)
		if err != nil {
			s.fail(w, err, "")
			return
		}
		if !ok {
			writeError(w, http.StatusNotFound, "not_found", "no such household", nil)
			return
		}
		h(w, r)
	}
}
