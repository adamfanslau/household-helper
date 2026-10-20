import Foundation
import Testing
@testable import HouseholdHelper

struct ListGroupingTests {
    private let t = Date(timeIntervalSince1970: 1_767_261_600)

    private func shop(_ id: String, _ name: String, _ order: Int) -> Shop {
        Shop(id: id, householdId: "h", name: name, sortOrder: order, createdAt: t, updatedAt: t, neededCount: 0)
    }

    private func item(_ name: String, shop: String?, status: ItemStatus = .needed) -> ShoppingListItem {
        ShoppingListItem(id: name, householdId: "h", name: name, shopId: shop, catalogItemId: nil, quantity: nil,
                         status: status, addedBy: nil, createdAt: t, updatedAt: t, boughtAt: status == .bought ? t : nil)
    }

    @Test func groupsByShopOrderUnsortedLastBoughtSeparate() {
        let shops = [shop("costco", "Costco", 1), shop("tj", "Trader Joe's", 0), shop("pharmacy", "Pharmacy", 2)]
        let items = [item("Milk", shop: "tj"), item("Batteries", shop: nil), item("Towels", shop: "costco"),
                     item("Eggs", shop: "tj", status: .bought), item("Bananas", shop: "tj")]
        let s = ListGrouping.sections(items: items, shops: shops)
        #expect(s.needed.map(\.title) == ["Trader Joe's", "Costco", "Unsorted"]) // Pharmacy hidden: no needed items
        #expect(s.needed[0].items.map(\.name) == ["Milk", "Bananas"])
        #expect(s.needed[2].shopID == nil && s.needed[2].items.map(\.name) == ["Batteries"])
        #expect(s.bought.map(\.name) == ["Eggs"])
        #expect(!s.isEmpty)
    }

    @Test func emptyAndUnknownShop() {
        #expect(ListGrouping.sections(items: [], shops: []).isEmpty)
        // An item whose shop vanished (deleted between fetches) has no section until the refetch
        // that clients do on a shops delete event.
        let s = ListGrouping.sections(items: [item("Ghost", shop: "gone")], shops: [])
        #expect(s.needed.isEmpty && s.bought.isEmpty)
    }

    @Test func basketItemsSinkToTheBottomOfTheirShop() {
        let shops = [shop("tj", "Trader Joe's", 0)]
        let items = [item("Milk", shop: "tj", status: .inBasket), item("Bananas", shop: "tj"), item("Eggs", shop: "tj", status: .inBasket), item("Jam", shop: "tj")]
        let s = ListGrouping.sections(items: items, shops: shops)
        #expect(s.needed[0].items.map(\.name) == ["Bananas", "Jam", "Milk", "Eggs"])
        #expect(s.needed[0].basketCount == 2)
        #expect(s.bought.isEmpty)
    }
}
