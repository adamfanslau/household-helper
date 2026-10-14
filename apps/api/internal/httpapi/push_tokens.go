package httpapi

import (
	"net/http"
	"strings"
)

// putPushToken registers the caller's FCM token: PUT /v1/me/push-tokens {token, platform} -> 204.
// A token already registered by another user moves to the caller (shared device, re-login).
func (s *Server) putPushToken(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	if !decode(w, r, &in) {
		return
	}
	in.Token = strings.TrimSpace(in.Token)
	in.Platform = strings.ToLower(strings.TrimSpace(in.Platform))
	fields := map[string]string{}
	if in.Token == "" || len(in.Token) > 4096 {
		fields["token"] = "required, at most 4096 characters"
	}
	if in.Platform != "ios" && in.Platform != "android" {
		fields["platform"] = "must be ios or android"
	}
	if len(fields) > 0 {
		invalid(w, "invalid push token", fields)
		return
	}
	if err := s.db.UpsertPushToken(r.Context(), in.Token, principal(r).UID, in.Platform); err != nil {
		s.fail(w, err, "")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// deletePushToken forgets the caller's token (clients call it before signing out): -> 204, idempotent.
func (s *Server) deletePushToken(w http.ResponseWriter, r *http.Request) {
	tok := r.PathValue("token")
	if tok == "" {
		invalid(w, "token required", nil)
		return
	}
	if err := s.db.DeletePushToken(r.Context(), tok, principal(r).UID); err != nil {
		s.fail(w, err, "")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
