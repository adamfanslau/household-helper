package httpapi

import (
	"net/http"
	"strings"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

func (s *Server) listShops(w http.ResponseWriter, r *http.Request) {
	out, err := s.db.ListShops(r.Context(), r.PathValue("hid"))
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createShop(w http.ResponseWriter, r *http.Request) {
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
	shop, err := s.db.CreateShop(r.Context(), r.PathValue("hid"), name)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	s.publish(r, "shops", "insert", shop)
	writeJSON(w, http.StatusCreated, shop)
}

func (s *Server) getShop(w http.ResponseWriter, r *http.Request) {
	shop, err := s.db.GetShop(r.Context(), r.PathValue("hid"), r.PathValue("shopId"))
	if err != nil {
		s.fail(w, err, "no such shop")
		return
	}
	writeJSON(w, http.StatusOK, shop)
}

func (s *Server) patchShop(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name      optString `json:"name"`
		SortOrder *int      `json:"sort_order"`
	}
	if !decode(w, r, &in) {
		return
	}
	var p store.ShopPatch
	if in.Name.Set {
		if in.Name.Value == nil {
			invalid(w, "name cannot be null", map[string]string{"name": "1-100 characters"})
			return
		}
		name, ok := validName(*in.Name.Value, 100)
		if !ok {
			invalid(w, "name must be 1-100 characters", map[string]string{"name": "1-100 characters"})
			return
		}
		p.Name = &name
	}
	if in.SortOrder != nil {
		if *in.SortOrder < 0 || *in.SortOrder > 1_000_000 {
			invalid(w, "sort_order out of range", map[string]string{"sort_order": "0-1000000"})
			return
		}
		p.SortOrder = in.SortOrder
	}
	if p.Name == nil && p.SortOrder == nil {
		invalid(w, "nothing to update", nil)
		return
	}
	shop, err := s.db.UpdateShop(r.Context(), r.PathValue("hid"), r.PathValue("shopId"), p)
	if err != nil {
		s.fail(w, err, "no such shop")
		return
	}
	s.publish(r, "shops", "update", shop)
	writeJSON(w, http.StatusOK, shop)
}

func (s *Server) deleteShop(w http.ResponseWriter, r *http.Request) {
	if err := s.db.DeleteShop(r.Context(), r.PathValue("hid"), r.PathValue("shopId")); err != nil {
		s.fail(w, err, "no such shop")
		return
	}
	// Items of the shop now have shop_id NULL; clients refetch items on a shop delete.
	s.publish(r, "shops", "delete", idRow{ID: r.PathValue("shopId")})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) listCatalog(w http.ResponseWriter, r *http.Request) {
	out, err := s.db.ListCatalog(r.Context(), r.PathValue("hid"))
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// defaultUnit validates an optional quantity hint; empty clears it.
func defaultUnit(in optString, fields map[string]string) *string {
	if !in.Set || in.Value == nil || *in.Value == "" {
		return nil
	}
	u := strings.TrimSpace(*in.Value)
	if len(u) > 50 {
		fields["default_unit"] = "max 50 characters"
		return nil
	}
	return &u
}

// upsertCatalogItem: POST /catalog-items {name, default_unit?, shop_id?} → 201 new / 200 existing (hints updated).
func (s *Server) upsertCatalogItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name        string    `json:"name"`
		DefaultUnit optString `json:"default_unit"`
		ShopID      *string   `json:"shop_id"`
	}
	if !decode(w, r, &in) {
		return
	}
	fields := map[string]string{}
	name, ok := validName(in.Name, 200)
	if !ok {
		fields["name"] = "required, 1-200 characters"
	}
	unit := defaultUnit(in.DefaultUnit, fields)
	if len(fields) > 0 {
		invalid(w, "invalid product", fields)
		return
	}
	c, created, err := s.db.UpsertCatalogItem(r.Context(), r.PathValue("hid"), name, unit, in.ShopID)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	if created {
		s.publish(r, "catalog_items", "insert", c)
		writeJSON(w, http.StatusCreated, c)
		return
	}
	s.publish(r, "catalog_items", "update", c)
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) patchCatalogItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name        *string   `json:"name"`
		DefaultUnit optString `json:"default_unit"`
		ShopID      optString `json:"shop_id"`
	}
	if !decode(w, r, &in) {
		return
	}
	fields := map[string]string{}
	var p store.CatalogPatch
	if in.Name != nil {
		n, ok := validName(*in.Name, 200)
		if !ok {
			fields["name"] = "1-200 characters"
		}
		p.Name = &n
	}
	if in.DefaultUnit.Set {
		p.DefaultUnit = store.Opt{Set: true, Value: defaultUnit(in.DefaultUnit, fields)}
	}
	if in.ShopID.Set {
		p.ShopID = store.Opt{Set: true, Value: in.ShopID.Value}
	}
	if p.Name == nil && !p.DefaultUnit.Set && !p.ShopID.Set {
		fields["body"] = "nothing to change"
	}
	if len(fields) > 0 {
		invalid(w, "invalid product patch", fields)
		return
	}
	c, err := s.db.UpdateCatalogItem(r.Context(), r.PathValue("hid"), r.PathValue("itemId"), p)
	if err != nil {
		s.fail(w, err, "no such product")
		return
	}
	s.publish(r, "catalog_items", "update", c)
	writeJSON(w, http.StatusOK, c)
}

func (s *Server) deleteCatalogItem(w http.ResponseWriter, r *http.Request) {
	if err := s.db.DeleteCatalogItem(r.Context(), r.PathValue("hid"), r.PathValue("itemId")); err != nil {
		s.fail(w, err, "no such product")
		return
	}
	s.publish(r, "catalog_items", "delete", idRow{ID: r.PathValue("itemId")})
	w.WriteHeader(http.StatusNoContent)
}
