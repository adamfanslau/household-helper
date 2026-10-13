package httpapi

import "net/http"

func (s *Server) routes(v1 *http.ServeMux) {
	v1.HandleFunc("GET /v1/me", s.me)

	v1.HandleFunc("GET /v1/households", s.listHouseholds)
	v1.HandleFunc("POST /v1/households", s.createHousehold)
	v1.HandleFunc("POST /v1/households/join", s.joinHousehold)
	v1.HandleFunc("GET /v1/households/{hid}", s.member(s.getHousehold))
	v1.HandleFunc("PATCH /v1/households/{hid}", s.member(s.patchHousehold))

	v1.HandleFunc("GET /v1/households/{hid}/invites", s.member(s.listInvites))
	v1.HandleFunc("POST /v1/households/{hid}/invites", s.member(s.createInvite))
	v1.HandleFunc("POST /v1/households/{hid}/invites/{id}/revoke", s.member(s.revokeInvite))

	v1.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not_found", "no such route", nil)
	})
}
