import Foundation
import Testing
@testable import HouseholdHelper

/// Port of the Expo applyChange semantics: insert de-dupes by id, update replaces, delete removes.
struct ChangeApplyTests {
    private func event(_ type: String, _ row: String) throws -> ChangeEvent {
        let json = """
        {"id":"e","table":"shopping_list_items","type":"\(type)","row":\(row),"actor":"dev-bob"}
        """
        return try JSON.decode(ChangeEvent.self, from: Data(json.utf8))
    }

    private func row(_ id: String, _ name: String, status: String = "needed") -> String {
        """
        {"id":"\(id)","household_id":"h","name":"\(name)","shop_id":null,"catalog_item_id":null,"quantity":null,
         "status":"\(status)","added_by":"dev-bob","created_at":"2026-01-01T10:00:00.000Z","updated_at":"2026-01-01T10:00:00.000Z",
         "bought_at":\(status == "bought" ? "\"2026-01-01T10:00:00.000Z\"" : "null")}
        """
    }

    @Test func insertUpdateDelete() throws {
        var items: [ShoppingListItem] = []
        items = ListStore.applied(items: items, change: try event("insert", row("a", "Milk")))
        items = ListStore.applied(items: items, change: try event("insert", row("a", "Milk"))) // echo of our own insert
        #expect(items.map(\.name) == ["Milk"])
        items = ListStore.applied(items: items, change: try event("update", row("a", "Oat milk", status: "bought")))
        #expect(items.first?.name == "Oat milk" && items.first?.status == .bought)
        items = ListStore.applied(items: items, change: try event("delete", "{\"id\":\"a\"}"))
        #expect(items.isEmpty)
        items = ListStore.applied(items: items, change: try event("delete", "{\"id\":\"missing\"}"))
        #expect(items.isEmpty)
    }
}
