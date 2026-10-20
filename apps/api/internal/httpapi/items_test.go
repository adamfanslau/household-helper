package httpapi

import (
	"strings"
	"testing"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// setup: A owns H with B as member; C owns another household.
func setupHouseholds(t *testing.T, e *env) (h store.Household, other store.Household) {
	t.Helper()
	e.expect(201, "a", "POST", "/v1/households", `{"name":"Home"}`, &h)
	var invites []store.Invite
	e.expect(200, "a", "GET", "/v1/households/"+h.ID+"/invites", "", &invites)
	e.expect(200, "b", "POST", "/v1/households/join", `{"code":"`+invites[0].Code+`"}`, nil)
	e.expect(201, "c", "POST", "/v1/households", `{"name":"C Home"}`, &other)
	return h, other
}

func TestShopsAndCatalog(t *testing.T) {
	e := newEnv(t)
	h, other := setupHouseholds(t, e)
	base := "/v1/households/" + h.ID

	var tj, costco, cshop store.Shop
	e.expect(201, "a", "POST", base+"/shops", `{"name":" Trader Joe's "}`, &tj)
	e.expect(201, "b", "POST", base+"/shops", `{"name":"Costco"}`, &costco)
	e.expect(201, "c", "POST", "/v1/households/"+other.ID+"/shops", `{"name":"C Shop"}`, &cshop)
	if tj.Name != "Trader Joe's" || tj.SortOrder != 0 || costco.SortOrder != 1 || tj.HouseholdID != h.ID {
		t.Fatalf("shops: %+v %+v", tj, costco)
	}
	code, body := e.as("a", "POST", base+"/shops", `{"name":""}`, nil)
	e.want(400, code, body)

	var shops []store.Shop
	e.expect(200, "b", "GET", base+"/shops", "", &shops)
	if len(shops) != 2 || shops[0].ID != tj.ID || shops[0].NeededCount != 0 {
		t.Fatalf("list: %+v", shops)
	}
	// Outsider: 404 on the household's shops, and A cannot reach C's shop through H.
	code, body = e.as("c", "GET", base+"/shops", "", nil)
	e.want(404, code, body)
	code, body = e.as("a", "GET", base+"/shops/"+cshop.ID, "", nil)
	e.want(404, code, body)
	code, body = e.as("a", "PATCH", base+"/shops/"+cshop.ID, `{"name":"x"}`, nil)
	e.want(404, code, body)

	// Reorder and rename.
	var moved store.Shop
	e.expect(200, "a", "PATCH", base+"/shops/"+costco.ID, `{"sort_order":0,"name":"Costco Wholesale"}`, &moved)
	if moved.SortOrder != 0 || moved.Name != "Costco Wholesale" {
		t.Fatalf("patch: %+v", moved)
	}
	code, body = e.as("a", "PATCH", base+"/shops/"+costco.ID, `{}`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "PATCH", base+"/shops/"+costco.ID, `{"name":null}`, nil)
	e.want(400, code, body)

	// Products: household-wide, keyed by name (case-insensitive), shop/quantity are hints.
	var milk, eggs store.CatalogItem
	e.expect(201, "a", "POST", base+"/catalog-items", `{"name":"Milk","default_unit":"1 gal","shop_id":"`+tj.ID+`"}`, &milk)
	e.expect(201, "a", "POST", base+"/catalog-items", `{"name":"Eggs"}`, &eggs)
	if milk.HouseholdID != h.ID || milk.ShopID == nil || *milk.ShopID != tj.ID || *milk.DefaultUnit != "1 gal" || eggs.ShopID != nil || eggs.DefaultUnit != nil {
		t.Fatalf("catalog: %+v %+v", milk, eggs)
	}
	var again store.CatalogItem
	e.expect(200, "a", "POST", base+"/catalog-items", `{"name":"milk","default_unit":"2 gal"}`, &again) // same product, hint updated
	if again.ID != milk.ID || *again.DefaultUnit != "2 gal" || *again.ShopID != tj.ID {
		t.Fatalf("upsert: %+v", again)
	}
	code, body = e.as("a", "POST", base+"/catalog-items", `{"name":"Nope","shop_id":"`+cshop.ID+`"}`, nil)
	e.want(400, code, body)
	code, body = e.as("c", "GET", base+"/catalog-items", "", nil)
	e.want(404, code, body)
	var cat []store.CatalogItem
	e.expect(200, "b", "GET", base+"/catalog-items", "", &cat)
	if len(cat) != 2 || cat[0].Name != "Eggs" || cat[1].Name != "Milk" {
		t.Fatalf("catalog sorted by name: %+v", cat)
	}
	var patched store.CatalogItem
	e.expect(200, "a", "PATCH", base+"/catalog-items/"+eggs.ID, `{"shop_id":"`+costco.ID+`","default_unit":"12"}`, &patched)
	if *patched.ShopID != costco.ID || *patched.DefaultUnit != "12" {
		t.Fatalf("patch: %+v", patched)
	}
	code, body = e.as("a", "PATCH", base+"/catalog-items/"+eggs.ID, `{"name":"Milk"}`, nil) // name taken
	e.want(409, code, body)
	code, body = e.as("c", "DELETE", base+"/catalog-items/"+eggs.ID, "", nil)
	e.want(404, code, body)
	code, body = e.as("a", "DELETE", base+"/catalog-items/"+eggs.ID, "", nil)
	e.want(204, code, body)
	e.expect(200, "a", "GET", base+"/catalog-items", "", &cat)
	if len(cat) != 1 {
		t.Fatalf("after delete: %+v", cat)
	}
	// Deleting a shop only clears the hint.
	code, body = e.as("a", "DELETE", base+"/shops/"+tj.ID, "", nil)
	e.want(204, code, body)
	e.expect(200, "a", "GET", base+"/catalog-items", "", &cat)
	if len(cat) != 1 || cat[0].ShopID != nil {
		t.Fatalf("shop delete should clear the hint: %+v", cat)
	}
}

func TestItems(t *testing.T) {
	e := newEnv(t)
	h, other := setupHouseholds(t, e)
	base := "/v1/households/" + h.ID
	var tj, costco, cshop store.Shop
	e.expect(201, "a", "POST", base+"/shops", `{"name":"Trader Joe's"}`, &tj)
	e.expect(201, "a", "POST", base+"/shops", `{"name":"Costco"}`, &costco)
	e.expect(201, "c", "POST", "/v1/households/"+other.ID+"/shops", `{"name":"C Shop"}`, &cshop)
	var milk store.CatalogItem
	e.expect(201, "a", "POST", base+"/catalog-items", `{"name":"Milk","default_unit":"1 gal","shop_id":"`+tj.ID+`"}`, &milk)

	// Plain add: Unsorted, needed, added_by from the token, never from the body; a product
	// of that name is created and linked.
	var oat store.ListItem
	e.expect(201, "b", "POST", base+"/items", `{"name":" Oat milk ","added_by":"a"}`, &oat)
	if oat.Name != "Oat milk" || oat.ShopID != nil || oat.Status != "needed" || oat.AddedBy == nil || *oat.AddedBy != "b" || oat.BoughtAt != nil || oat.CatalogItemID == nil {
		t.Fatalf("oat: %+v", oat)
	}
	var cat []store.CatalogItem
	e.expect(200, "a", "GET", base+"/catalog-items", "", &cat)
	if len(cat) != 2 || cat[1].Name != "Oat milk" || cat[1].ID != *oat.CatalogItemID {
		t.Fatalf("product auto-created: %+v", cat)
	}
	// By name, with a shop and quantity: the product remembers both as hints.
	var oat2 store.ListItem
	e.expect(201, "b", "POST", base+"/items", `{"name":"oat MILK","shop_id":"`+costco.ID+`","quantity":"2"}`, &oat2)
	if oat2.Name != "Oat milk" || *oat2.CatalogItemID != *oat.CatalogItemID {
		t.Fatalf("same product by name: %+v", oat2)
	}
	e.expect(200, "a", "GET", base+"/catalog-items", "", &cat)
	if *cat[1].ShopID != costco.ID || *cat[1].DefaultUnit != "2" {
		t.Fatalf("hints not remembered: %+v", cat[1])
	}
	// From the catalog: shop and quantity come from the product's hints.
	var fromCat store.ListItem
	e.expect(201, "a", "POST", base+"/items", `{"name":"Milk","catalog_item_id":"`+milk.ID+`"}`, &fromCat)
	if fromCat.ShopID == nil || *fromCat.ShopID != tj.ID || fromCat.Quantity == nil || *fromCat.Quantity != "1 gal" || fromCat.CatalogItemID == nil {
		t.Fatalf("from catalog: %+v", fromCat)
	}
	// Explicit values win and become the new hints.
	var explicit store.ListItem
	e.expect(201, "a", "POST", base+"/items", `{"name":"Milk","catalog_item_id":"`+milk.ID+`","quantity":"2 gal","shop_id":"`+costco.ID+`"}`, &explicit)
	if *explicit.Quantity != "2 gal" || *explicit.ShopID != costco.ID {
		t.Fatalf("explicit values lost: %+v", explicit)
	}
	var milkNow store.CatalogItem
	e.expect(200, "a", "POST", base+"/catalog-items", `{"name":"Milk"}`, &milkNow)
	if *milkNow.ShopID != costco.ID || *milkNow.DefaultUnit != "2 gal" {
		t.Fatalf("milk hints: %+v", milkNow)
	}
	// Cross-household references are 400, not silently accepted.
	code, body := e.as("a", "POST", base+"/items", `{"name":"X","shop_id":"`+cshop.ID+`"}`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "POST", base+"/items", `{"name":"X","catalog_item_id":"00000000-0000-4000-8000-000000000000"}`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "POST", base+"/items", `{"name":"X","id":"not-a-uuid"}`, nil)
	e.want(400, code, body)
	code, body = e.as("c", "POST", base+"/items", `{"name":"X"}`, nil)
	e.want(404, code, body)

	// Idempotent retry with a client id: 201 then 200 with the same row.
	const cid = "0199c6f0-0000-7000-8000-000000000001"
	var first, again store.ListItem
	e.expect(201, "a", "POST", base+"/items", `{"id":"`+cid+`","name":"Coffee"}`, &first)
	e.expect(200, "a", "POST", base+"/items", `{"id":"`+cid+`","name":"Coffee"}`, &again)
	if first.ID != cid || again.ID != cid {
		t.Fatalf("client id: %+v %+v", first, again)
	}

	// Basket + checkout: in_basket keeps the item on the list; checkout per shop marks bought.
	var basket store.ListItem
	e.expect(200, "a", "PATCH", base+"/items/"+fromCat.ID, `{"status":"in_basket"}`, &basket)
	if basket.Status != "in_basket" || basket.BoughtAt != nil {
		t.Fatalf("in_basket: %+v", basket)
	}
	e.expect(200, "a", "PATCH", base+"/items/"+oat2.ID, `{"status":"in_basket"}`, nil) // Costco
	var checked []store.ListItem
	e.expect(200, "a", "POST", base+"/items/checkout", `{"shop_id":"`+tj.ID+`"}`, &checked)
	if len(checked) != 1 || checked[0].ID != fromCat.ID || checked[0].Status != "bought" || checked[0].BoughtAt == nil {
		t.Fatalf("checkout TJ: %+v", checked)
	}
	e.expect(200, "a", "POST", base+"/items/checkout", `{"shop_id":null}`, &checked) // Unsorted: nothing in basket
	if len(checked) != 0 {
		t.Fatalf("checkout unsorted: %+v", checked)
	}
	e.expect(200, "a", "POST", base+"/items/checkout", `{}`, &checked) // everything left in the basket
	if len(checked) != 1 || checked[0].ID != oat2.ID {
		t.Fatalf("checkout all: %+v", checked)
	}
	code, body = e.as("a", "PATCH", base+"/items/"+oat.ID, `{"status":"maybe"}`, nil)
	e.want(400, code, body)
	e.expect(200, "a", "PATCH", base+"/items/"+fromCat.ID, `{"status":"needed"}`, nil)
	e.expect(200, "a", "PATCH", base+"/items/"+oat2.ID, `{"status":"needed"}`, nil)

	// needed_count on shops.
	var shops []store.Shop
	e.expect(200, "b", "GET", base+"/shops", "", &shops)
	if shops[0].NeededCount != 1 || shops[1].NeededCount != 2 { // Milk from hints at TJ; Oat milk + explicit Milk at Costco
		t.Fatalf("needed_count: %+v", shops)
	}

	// Toggle bought: server sets bought_at, and clears it on un-buy.
	var toggled store.ListItem
	e.expect(200, "b", "PATCH", base+"/items/"+oat.ID, `{"status":"bought"}`, &toggled)
	if toggled.Status != "bought" || toggled.BoughtAt == nil {
		t.Fatalf("bought: %+v", toggled)
	}
	e.expect(200, "a", "PATCH", base+"/items/"+oat.ID, `{"status":"needed"}`, &toggled)
	if toggled.Status != "needed" || toggled.BoughtAt != nil {
		t.Fatalf("un-buy: %+v", toggled)
	}
	code, body = e.as("a", "PATCH", base+"/items/"+oat.ID, `{"status":"maybe"}`, nil)
	e.want(400, code, body)

	// Move to a shop, edit quantity, then back to Unsorted and clear quantity.
	e.expect(200, "a", "PATCH", base+"/items/"+oat.ID, `{"shop_id":"`+costco.ID+`","quantity":"2"}`, &toggled)
	if toggled.ShopID == nil || *toggled.ShopID != costco.ID || *toggled.Quantity != "2" {
		t.Fatalf("move: %+v", toggled)
	}
	e.expect(200, "a", "PATCH", base+"/items/"+oat.ID, `{"shop_id":null,"quantity":null,"name":"Oat Milk"}`, &toggled)
	if toggled.ShopID != nil || toggled.Quantity != nil || toggled.Name != "Oat Milk" {
		t.Fatalf("unsort: %+v", toggled)
	}
	code, body = e.as("a", "PATCH", base+"/items/"+oat.ID, `{"shop_id":"`+cshop.ID+`"}`, nil)
	e.want(400, code, body)
	code, body = e.as("a", "PATCH", base+"/items/"+oat.ID, `{}`, nil)
	e.want(400, code, body)
	code, body = e.as("c", "PATCH", base+"/items/"+oat.ID, `{"status":"bought"}`, nil)
	e.want(404, code, body)
	code, body = e.as("c", "DELETE", base+"/items/"+oat.ID, "", nil)
	e.want(404, code, body)

	// List includes bought items; clear bought removes only those.
	e.expect(200, "a", "PATCH", base+"/items/"+fromCat.ID, `{"status":"bought"}`, nil)
	e.expect(200, "a", "PATCH", base+"/items/"+explicit.ID, `{"status":"bought"}`, nil)
	var items []store.ListItem
	e.expect(200, "b", "GET", base+"/items", "", &items)
	if len(items) != 5 { // Oat milk x2, Milk x2 (bought), Coffee
		t.Fatalf("list: %d", len(items))
	}
	code, body = e.as("a", "DELETE", base+"/items", "", nil)
	e.want(400, code, body)
	code, body = e.as("a", "DELETE", base+"/items?status=bought", "", nil)
	e.want(204, code, body)
	e.expect(200, "b", "GET", base+"/items", "", &items)
	if len(items) != 3 || items[0].Status != "needed" || items[1].Status != "needed" || items[2].Status != "needed" {
		t.Fatalf("after clear: %+v", items)
	}

	// Delete an item; deleting a shop un-sorts its items.
	code, body = e.as("b", "DELETE", base+"/items/"+first.ID, "", nil)
	e.want(204, code, body)
	code, body = e.as("b", "DELETE", base+"/items/"+first.ID, "", nil)
	e.want(404, code, body)
	e.expect(201, "a", "POST", base+"/items", `{"name":"Bananas","shop_id":"`+tj.ID+`"}`, &toggled)
	code, body = e.as("a", "DELETE", base+"/shops/"+tj.ID, "", nil)
	e.want(204, code, body)
	var bananas store.ListItem
	e.expect(200, "a", "GET", base+"/items", "", &items)
	for _, it := range items {
		if it.Name == "Bananas" {
			bananas = it
		}
	}
	if bananas.ID == "" || bananas.ShopID != nil {
		t.Fatalf("shop delete should unsort: %+v", bananas)
	}
	code, body = e.as("a", "GET", base+"/shops/"+tj.ID, "", nil)
	e.want(404, code, body)
	if !strings.Contains(body, "no such shop") {
		t.Fatalf("body: %s", body)
	}
}
