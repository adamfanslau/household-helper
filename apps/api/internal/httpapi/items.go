package httpapi

import (
	"net/http"
	"strings"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
	"github.com/google/uuid"
)

func (s *Server) listItems(w http.ResponseWriter, r *http.Request) {
	out, err := s.db.ListItems(r.Context(), r.PathValue("hid"))
	if err != nil {
		s.fail(w, err, "")
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// quantity trims and caps a free-text quantity; empty means null.
func quantity(v *string) (*string, bool) {
	if v == nil {
		return nil, true
	}
	q := strings.TrimSpace(*v)
	if q == "" {
		return nil, true
	}
	if len(q) > 50 {
		return nil, false
	}
	return &q, true
}

func validUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}

func (s *Server) createItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ID            string  `json:"id"`
		Name          string  `json:"name"`
		ShopID        *string `json:"shop_id"`
		CatalogItemID *string `json:"catalog_item_id"`
		Quantity      *string `json:"quantity"`
	}
	if !decode(w, r, &in) {
		return
	}
	fields := map[string]string{}
	name, ok := validName(in.Name, 200)
	if !ok {
		fields["name"] = "required, 1-200 characters"
	}
	if in.ID != "" && !validUUID(in.ID) {
		fields["id"] = "must be a UUID when provided"
	}
	qty, ok := quantity(in.Quantity)
	if !ok {
		fields["quantity"] = "max 50 characters"
	}
	if len(fields) > 0 {
		invalid(w, "invalid item", fields)
		return
	}
	res, err := s.db.CreateItem(r.Context(), r.PathValue("hid"), principal(r).UID, store.NewItem{
		ID: in.ID, Name: name, ShopID: in.ShopID, CatalogItemID: in.CatalogItemID, Quantity: qty,
	})
	if err != nil {
		s.fail(w, err, "")
		return
	}
	if res.Created {
		if res.Catalog != nil {
			typ := "update"
			if res.CatalogCreated {
				typ = "insert"
			}
			s.publish(r, "catalog_items", typ, *res.Catalog)
		}
		s.publish(r, "shopping_list_items", "insert", res.Item)
		writeJSON(w, http.StatusCreated, res.Item)
		return
	}
	writeJSON(w, http.StatusOK, res.Item) // idempotent retry with the same client id
}

func (s *Server) patchItem(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name     optString `json:"name"`
		Quantity optString `json:"quantity"`
		ShopID   optString `json:"shop_id"`
		Status   *string   `json:"status"`
	}
	if !decode(w, r, &in) {
		return
	}
	var p store.ItemPatch
	fields := map[string]string{}
	if in.Name.Set {
		if in.Name.Value == nil {
			fields["name"] = "cannot be null"
		} else if name, ok := validName(*in.Name.Value, 200); ok {
			p.Name = &name
		} else {
			fields["name"] = "1-200 characters"
		}
	}
	if in.Quantity.Set {
		if q, ok := quantity(in.Quantity.Value); ok {
			p.Quantity = store.Opt{Set: true, Value: q}
		} else {
			fields["quantity"] = "max 50 characters"
		}
	}
	if in.ShopID.Set {
		if in.ShopID.Value != nil && !validUUID(*in.ShopID.Value) {
			fields["shop_id"] = "must be a UUID or null"
		} else {
			p.ShopID = store.Opt{Set: true, Value: in.ShopID.Value}
		}
	}
	if in.Status != nil {
		if *in.Status != "needed" && *in.Status != "in_basket" && *in.Status != "bought" {
			fields["status"] = "needed, in_basket or bought"
		} else {
			p.Status = in.Status
		}
	}
	if len(fields) > 0 {
		invalid(w, "invalid item", fields)
		return
	}
	if p.Name == nil && !p.Quantity.Set && !p.ShopID.Set && p.Status == nil {
		invalid(w, "nothing to update", nil)
		return
	}
	item, err := s.db.UpdateItem(r.Context(), r.PathValue("hid"), r.PathValue("itemId"), p)
	if err != nil {
		s.fail(w, err, "no such item")
		return
	}
	s.publish(r, "shopping_list_items", "update", item)
	writeJSON(w, http.StatusOK, item)
}

func (s *Server) deleteItem(w http.ResponseWriter, r *http.Request) {
	if err := s.db.DeleteItem(r.Context(), r.PathValue("hid"), r.PathValue("itemId")); err != nil {
		s.fail(w, err, "no such item")
		return
	}
	s.publish(r, "shopping_list_items", "delete", idRow{ID: r.PathValue("itemId")})
	w.WriteHeader(http.StatusNoContent)
}

// clearBought handles DELETE /items?status=bought ("Clear recently bought").
func (s *Server) clearBought(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("status") != "bought" {
		invalid(w, "bulk delete needs ?status=bought", map[string]string{"status": "bought"})
		return
	}
	deleted, err := s.db.ClearBought(r.Context(), r.PathValue("hid"))
	if err != nil {
		s.fail(w, err, "")
		return
	}
	for _, id := range deleted {
		s.publish(r, "shopping_list_items", "delete", idRow{ID: id})
	}
	w.WriteHeader(http.StatusNoContent)
}

// checkout marks in-basket items bought: body {} = all, {"shop_id":"<id>"} = that shop,
// {"shop_id":null} = Unsorted. Returns the updated items and publishes one update each.
func (s *Server) checkout(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ShopID optString `json:"shop_id"`
	}
	if !decode(w, r, &in) {
		return
	}
	scope := store.Opt{Set: in.ShopID.Set, Value: in.ShopID.Value}
	items, err := s.db.Checkout(r.Context(), r.PathValue("hid"), scope)
	if err != nil {
		s.fail(w, err, "")
		return
	}
	for _, it := range items {
		s.publish(r, "shopping_list_items", "update", it)
	}
	writeJSON(w, http.StatusOK, items)
}
