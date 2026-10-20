// Pure grouping for the List tab: needed items by shop in sort_order, Unsorted last,
// bought items separate ("Recently bought"). Port of the Expo useMemo in (tabs)/index.tsx.
import Foundation

nonisolated enum ListGrouping {
    static let unsortedID = "__unsorted__"

    struct Section: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let shopID: String?
        let items: [ShoppingListItem]   // needed first, in-basket last (in arrival order within each)
        var basketCount: Int { items.filter { $0.status == .inBasket }.count }
    }

    struct Sections: Hashable, Sendable {
        let needed: [Section]
        let bought: [ShoppingListItem]
        var isEmpty: Bool { needed.isEmpty && bought.isEmpty }
    }

    static func sections(items: [ShoppingListItem], shops: [Shop]) -> Sections {
        var byShop: [String: [ShoppingListItem]] = [:]
        var bought: [ShoppingListItem] = []
        for item in items {
            if item.status == .bought {
                bought.append(item)
            } else {
                byShop[item.shopId ?? unsortedID, default: []].append(item)
            }
        }
        for key in byShop.keys {
            // Ticked items sink to the bottom of their shop so what is still to find stays on top.
            byShop[key] = byShop[key]!.filter { $0.status != .inBasket } + byShop[key]!.filter { $0.status == .inBasket }
        }
        var needed: [Section] = []
        for shop in shops.sorted(by: { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }) {
            if let list = byShop[shop.id], !list.isEmpty {
                needed.append(Section(id: shop.id, title: shop.name, shopID: shop.id, items: list))
            }
        }
        if let list = byShop[unsortedID], !list.isEmpty {
            needed.append(Section(id: unsortedID, title: "Unsorted", shopID: nil, items: list))
        }
        return Sections(needed: needed, bought: bought)
    }
}
