package httpapi

import (
	"net/http"

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
	out, err := s.db.ListCatalog(r.Context(), r.PathValue("hid"), r.PathValue("shopId"))
	if err != nil {
		s.fail(w, err, "no such shop")
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) createCatalogItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name        string    `json:"name"`
		DefaultUnit optString `json:"default_unit"`
	}
	if !decode(w, r, &in) {
		return
	}
	name, ok := validName(in.Name, 100)
	if !ok {
		invalid(w, "name must be 1-100 characters", map[string]string{"name": "required, 1-100 characters"})
		return
	}
	var unit *string
	if in.DefaultUnit.Set && in.DefaultUnit.Value != nil && *in.DefaultUnit.Value != "" {
		if len(*in.DefaultUnit.Value) > 50 {
			invalid(w, "default_unit too long", map[string]string{"default_unit": "max 50 characters"})
			return
		}
		unit = in.DefaultUnit.Value
	}
	c, err := s.db.CreateCatalogItem(r.Context(), r.PathValue("hid"), r.PathValue("shopId"), name, unit)
	if err != nil {
		s.fail(w, err, "no such shop")
		return
	}
	s.publish(r, "catalog_items", "insert", c)
	writeJSON(w, http.StatusCreated, c)
}

func (s *Server) deleteCatalogItem(w http.ResponseWriter, r *http.Request) {
	if err := s.db.DeleteCatalogItem(r.Context(), r.PathValue("hid"), r.PathValue("shopId"), r.PathValue("itemId")); err != nil {
		s.fail(w, err, "no such catalog item")
		return
	}
	s.publish(r, "catalog_items", "delete", catalogDeleteRow{ID: r.PathValue("itemId"), ShopID: r.PathValue("shopId")})
	w.WriteHeader(http.StatusNoContent)
}
