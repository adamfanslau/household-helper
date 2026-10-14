package httpapi

import "net/http"

func (s *Server) routes(v1 *http.ServeMux) {
	v1.HandleFunc("GET /v1/me", s.me)
	v1.HandleFunc("PUT /v1/me/push-tokens", s.putPushToken)
	v1.HandleFunc("DELETE /v1/me/push-tokens/{token}", s.deletePushToken)

	v1.HandleFunc("GET /v1/households", s.listHouseholds)
	v1.HandleFunc("POST /v1/households", s.createHousehold)
	v1.HandleFunc("POST /v1/households/join", s.joinHousehold)
	v1.HandleFunc("GET /v1/households/{hid}", s.member(s.getHousehold))
	v1.HandleFunc("PATCH /v1/households/{hid}", s.member(s.patchHousehold))

	v1.HandleFunc("GET /v1/households/{hid}/invites", s.member(s.listInvites))
	v1.HandleFunc("POST /v1/households/{hid}/invites", s.member(s.createInvite))
	v1.HandleFunc("POST /v1/households/{hid}/invites/{id}/revoke", s.member(s.revokeInvite))

	v1.HandleFunc("GET /v1/households/{hid}/shops", s.member(s.listShops))
	v1.HandleFunc("POST /v1/households/{hid}/shops", s.member(s.createShop))
	v1.HandleFunc("GET /v1/households/{hid}/shops/{shopId}", s.member(s.getShop))
	v1.HandleFunc("PATCH /v1/households/{hid}/shops/{shopId}", s.member(s.patchShop))
	v1.HandleFunc("DELETE /v1/households/{hid}/shops/{shopId}", s.member(s.deleteShop))
	v1.HandleFunc("GET /v1/households/{hid}/shops/{shopId}/catalog-items", s.member(s.listCatalog))
	v1.HandleFunc("POST /v1/households/{hid}/shops/{shopId}/catalog-items", s.member(s.createCatalogItem))
	v1.HandleFunc("DELETE /v1/households/{hid}/shops/{shopId}/catalog-items/{itemId}", s.member(s.deleteCatalogItem))

	v1.HandleFunc("GET /v1/households/{hid}/items", s.member(s.listItems))
	v1.HandleFunc("POST /v1/households/{hid}/items", s.member(s.createItem))
	v1.HandleFunc("DELETE /v1/households/{hid}/items", s.member(s.clearBought))
	v1.HandleFunc("PATCH /v1/households/{hid}/items/{itemId}", s.member(s.patchItem))
	v1.HandleFunc("DELETE /v1/households/{hid}/items/{itemId}", s.member(s.deleteItem))

	v1.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "not_found", "no such route", nil)
	})
}
