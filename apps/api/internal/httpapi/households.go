package httpapi

import (
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
	"golang.org/x/time/rate"
)

func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	p := principal(r)
	u, err := s.db.GetUser(r.Context(), p.UID)
	if err == store.ErrNotFound { // ensure throttle cache survived a user row delete
		if err = s.db.EnsureUser(r.Context(), p.UID, p.Email, p.Name, p.Provider); err == nil {
			u, err = s.db.GetUser(r.Context(), p.UID)
		}
	}
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func validName(name string, max int) (string, bool) {
	name = strings.TrimSpace(name)
	n := utf8.RuneCountInString(name)
	return name, n >= 1 && n <= max
}

func (s *Server) listHouseholds(w http.ResponseWriter, r *http.Request) {
	hs, err := s.db.ListHouseholds(r.Context(), principal(r).UID)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, hs)
}

func (s *Server) createHousehold(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name string `json:"name"`
	}
	if !decode(w, r, &in) {
		return
	}
	name, ok := validName(in.Name, 100)
	if !ok {
		invalid(w, "name must be 1-100 characters", map[string]string{"name": "required, 1-100 characters"})
		return
	}
	h, err := s.db.CreateHousehold(r.Context(), principal(r).UID, name)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusCreated, h)
}

func (s *Server) getHousehold(w http.ResponseWriter, r *http.Request) {
	h, err := s.db.GetHousehold(r.Context(), r.PathValue("hid"), principal(r).UID)
	if err != nil {
		s.fail(w, err, "no such household")
		return
	}
	writeJSON(w, http.StatusOK, h)
}

func (s *Server) patchHousehold(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name optString `json:"name"`
	}
	if !decode(w, r, &in) {
		return
	}
	if !in.Name.Set || in.Name.Value == nil {
		invalid(w, "nothing to update", map[string]string{"name": "required"})
		return
	}
	name, ok := validName(*in.Name.Value, 100)
	if !ok {
		invalid(w, "name must be 1-100 characters", map[string]string{"name": "1-100 characters"})
		return
	}
	h, err := s.db.UpdateHouseholdName(r.Context(), r.PathValue("hid"), principal(r).UID, name)
	if err != nil {
		s.fail(w, err, "no such household")
		return
	}
	writeJSON(w, http.StatusOK, h)
}

// joinHousehold is rate-limited per uid so invite codes cannot be brute-forced
// (32^8 codes; 10 attempts a minute keeps that infeasible).
func (s *Server) joinHousehold(w http.ResponseWriter, r *http.Request) {
	p := principal(r)
	if !s.joinLimiter(p.UID).Allow() {
		writeError(w, http.StatusTooManyRequests, "rate_limited", "too many join attempts, try again in a minute", nil)
		return
	}
	var in struct {
		Code string `json:"code"`
	}
	if !decode(w, r, &in) {
		return
	}
	code := strings.ToUpper(strings.TrimSpace(in.Code))
	if !ids.ValidInviteCode(code) {
		invalid(w, "invite code must be 8 letters or digits", map[string]string{"code": "8 characters"})
		return
	}
	h, err := s.db.JoinHousehold(r.Context(), p.UID, code)
	if err != nil {
		s.fail(w, err, "invalid or expired invite code")
		return
	}
	writeJSON(w, http.StatusOK, h)
}

func (s *Server) joinLimiter(uid string) *rate.Limiter {
	s.joins.mu.Lock()
	defer s.joins.mu.Unlock()
	if len(s.joins.m) > 10000 {
		s.joins.m = map[string]*rate.Limiter{}
	}
	l, ok := s.joins.m[uid]
	if !ok {
		l = rate.NewLimiter(rate.Limit(10.0/60.0), 10)
		s.joins.m[uid] = l
	}
	return l
}

func (s *Server) listInvites(w http.ResponseWriter, r *http.Request) {
	inv, err := s.db.ListInvites(r.Context(), r.PathValue("hid"))
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, inv)
}

func (s *Server) createInvite(w http.ResponseWriter, r *http.Request) {
	inv, err := s.db.CreateInvite(r.Context(), r.PathValue("hid"), principal(r).UID)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusCreated, inv)
}

func (s *Server) revokeInvite(w http.ResponseWriter, r *http.Request) {
	inv, err := s.db.RevokeInvite(r.Context(), r.PathValue("hid"), r.PathValue("id"))
	if err != nil {
		s.fail(w, err, "no such invite")
		return
	}
	writeJSON(w, http.StatusOK, inv)
}
