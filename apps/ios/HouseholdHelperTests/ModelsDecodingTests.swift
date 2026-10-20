// Decodes the API's golden fixtures (apps/api/internal/httpapi/testdata/golden). A failure here
// means the Go wire shape changed: update API.md, `make golden`, then the Swift models.
import Foundation
import Testing
@testable import HouseholdHelper

private final class BundleToken {}

struct ModelsDecodingTests {
    private func golden(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "golden")
            ?? bundle.url(forResource: name, withExtension: "json") else {
            throw NSError(domain: "golden", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name).json"])
        }
        return try Data(contentsOf: url)
    }

    @Test func me() throws {
        let m = try JSON.decode(Me.self, from: golden("me"))
        #expect(m.id == "dev-alice" && m.displayName == "Alice" && m.provider == "password")
    }

    @Test func household() throws {
        let h = try JSON.decode(Household.self, from: golden("household"))
        #expect(h.name == "Mock Household" && h.role == "owner" && h.createdBy == "dev-alice")
        #expect(h.createdAt == JSON.parseDate("2026-01-01T10:00:00.000Z"))
    }

    @Test func invite() throws {
        let i = try JSON.decode(Invite.self, from: golden("invite"))
        #expect(i.code == "MOCK1234" && i.revokedAt == nil && i.expiresAt == nil)
    }

    @Test func shop() throws {
        let s = try JSON.decode(Shop.self, from: golden("shop"))
        #expect(s.name == "Trader Joe's" && s.sortOrder == 0 && s.neededCount == 2)
    }

    @Test func catalogItem() throws {
        let c = try JSON.decode(CatalogItem.self, from: golden("catalog_item"))
        #expect(c.name == "Milk" && c.defaultUnit == "1 gal" && c.householdId == "11111111-1111-4111-8111-111111111111" && c.shopId != nil)
    }

    @Test func shoppingListItem() throws {
        let item = try JSON.decode(ShoppingListItem.self, from: golden("shopping_list_item"))
        #expect(item.status == .bought && item.quantity == "1 gal" && item.boughtAt != nil && item.shopId != nil)
    }

    @Test func sseChange() throws {
        let e = try JSON.decode(ChangeEvent.self, from: golden("sse_change"))
        #expect(e.table == "shopping_list_items" && e.type == "update" && e.actor == "dev-bob")
        #expect(e.row["name"]?.stringValue == "Milk")
        // The row decodes as the table's model.
        let data = try JSONEncoder().encode(e.row)
        let item = try JSON.decode(ShoppingListItem.self, from: data)
        #expect(item.status == .bought)
    }

    @Test func errorEnvelope() throws {
        let e = try JSON.decode(ApiErrorBody.self, from: golden("error"))
        #expect(e.error.code == "invalid_request" && e.error.fields?["name"] != nil)
    }

    @Test func datesWithAndWithoutFractions() {
        #expect(JSON.parseDate("2026-01-01T10:00:00.000Z") != nil)
        #expect(JSON.parseDate("2026-01-01T10:00:00Z") != nil)
        #expect(JSON.parseDate("yesterday") == nil)
    }
}
