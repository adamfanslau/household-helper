import Foundation
import OSLog
import Observation

/// Items and shops of the selected household with optimistic mutations, delayed deletes
/// with undo, and SSE change application.
@Observable
final class ListStore {
    private(set) var items: [ShoppingListItem] = []
    private(set) var shops: [Shop] = []
    /// The household's products (typing hints), kept in step over SSE.
    private(set) var products: [CatalogItem] = []
    private(set) var loading = false
    private(set) var loadedHouseholdID: String?
    var error: String?

    struct PendingDelete: Identifiable {
        let id: String
        let item: ShoppingListItem
        var task: Task<Void, Never>?
    }
    /// Items removed from view, deleted on the server after a grace period unless undone.
    private(set) var pendingDeletes: [PendingDelete] = []

    private let api: ApiClient
    private var hid: String? { loadedHouseholdID }

    init(api: ApiClient) {
        self.api = api
    }

    var sections: ListGrouping.Sections {
        ListGrouping.sections(items: items, shops: shops)
    }

    func shop(_ id: String?) -> Shop? {
        guard let id else { return nil }
        return shops.first { $0.id == id }
    }

    /// Items still to buy at a shop (needed + in the basket), derived from the live list so it
    /// updates on every change, including ones that arrive over SSE.
    func openCount(for shopID: String) -> Int {
        items.filter { $0.shopId == shopID && $0.status != .bought }.count
    }

    /// Shops with the most to buy first; ties keep the household's order.
    var shopsByActivity: [Shop] {
        shops.sorted { a, b in
            let (ca, cb) = (openCount(for: a.id), openCount(for: b.id))
            if ca != cb { return ca > cb }
            return (a.sortOrder, a.createdAt) < (b.sortOrder, b.createdAt)
        }
    }

    // MARK: loading

    func load(householdID: String) async {
        loading = loadedHouseholdID != householdID
        defer { loading = false }
        do {
            async let i: [ShoppingListItem] = api.get("/v1/households/\(householdID)/items")
            async let s: [Shop] = api.get("/v1/households/\(householdID)/shops")
            async let p: [CatalogItem] = api.get("/v1/households/\(householdID)/catalog-items")
            let (loadedItems, loadedShops, loadedProducts) = try await (i, s, p)
            let hidden = Set(pendingDeletes.map(\.id))
            items = loadedItems.filter { !hidden.contains($0.id) }
            shops = loadedShops
            products = loadedProducts
            loadedHouseholdID = householdID
            error = nil
            Log.api.info("list loaded: \(self.items.count) items, \(self.shops.count) shops")
        } catch {
            self.error = error.localizedDescription
            Log.api.error("list load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() async {
        if let hid { await load(householdID: hid) }
    }

    func clear() {
        for p in pendingDeletes { p.task?.cancel() }
        pendingDeletes = []
        items = []
        shops = []
        products = []
        loadedHouseholdID = nil
    }

    /// Products matching what the user typed: prefix matches first, then anywhere in the name.
    func suggestions(for query: String, limit: Int = 6) -> [CatalogItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let prefix = products.filter { $0.name.lowercased().hasPrefix(q) }
        let inside = products.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        return Array((prefix + inside).prefix(limit))
    }

    // MARK: items

    struct NewItemBody: Encodable {
        var id: String
        var name: String
        var shopId: String?
        var catalogItemId: String?
        var quantity: String?
    }

    /// Adds optimistically with a client id so the server echo (and a retry) de-duplicate.
    func add(name: String, shopID: String? = nil, catalogItemID: String? = nil, quantity: String? = nil) async {
        guard let hid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString.lowercased()
        let now = Date()
        let optimistic = ShoppingListItem(id: id, householdId: hid, name: trimmed, shopId: shopID, catalogItemId: catalogItemID,
                                          quantity: quantity, status: .needed, addedBy: nil, createdAt: now, updatedAt: now, boughtAt: nil)
        items.append(optimistic)
        do {
            let saved: ShoppingListItem = try await api.post("/v1/households/\(hid)/items",
                NewItemBody(id: id, name: trimmed, shopId: shopID, catalogItemId: catalogItemID, quantity: quantity))
            replace(saved)
            bumpNeeded(shopID: saved.shopId, by: 1)
        } catch {
            items.removeAll { $0.id == id }
            self.error = error.localizedDescription
        }
    }

    struct PatchBody: Encodable {
        var name: String?
        var quantity: String??
        var shopId: String??
        var status: ItemStatus?

        enum CodingKeys: String, CodingKey { case name, quantity, shopId, status }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let name { try c.encode(name, forKey: .name) }
            if let quantity { try c.encode(quantity, forKey: .quantity) } // nil inside = JSON null
            if let shopId { try c.encode(shopId, forKey: .shopId) }
            if let status { try c.encode(status, forKey: .status) }
        }
    }

    private func patch(_ item: ShoppingListItem, _ body: PatchBody, optimistic: ShoppingListItem) async {
        guard let hid else { return }
        let before = item
        replace(optimistic)
        do {
            let saved: ShoppingListItem = try await api.patch("/v1/households/\(hid)/items/\(item.id)", body)
            replace(saved)
        } catch {
            replace(before)
            self.error = error.localizedDescription
        }
    }

    /// Tap: needed ⇄ in the basket; a bought item goes back to needed (un-buy).
    func toggle(_ item: ShoppingListItem) async {
        var next = item
        next.status = item.status == .needed ? .inBasket : .needed
        next.boughtAt = nil
        if item.status == .bought { bumpNeeded(shopID: item.shopId, by: 1) }
        await patch(item, PatchBody(status: next.status), optimistic: next)
    }

    /// Swipe / menu: straight to bought (skipping the basket).
    func markBought(_ item: ShoppingListItem) async {
        guard item.status != .bought else { return }
        var next = item
        next.status = .bought
        next.boughtAt = Date()
        bumpNeeded(shopID: item.shopId, by: -1)
        await patch(item, PatchBody(status: .bought), optimistic: next)
    }

    /// Checkout: everything in the basket for one shop (`.some(nil)` = Unsorted, `nil` = all) becomes bought.
    func checkout(shopID: String??) async {
        guard let hid else { return }
        let scope: (ShoppingListItem) -> Bool = { item in
            guard item.status == .inBasket else { return false }
            switch shopID {
            case .none: return true
            case .some(let id): return item.shopId == id
            }
        }
        let before = items
        let now = Date()
        for i in items.indices where scope(items[i]) {
            items[i].status = .bought
            items[i].boughtAt = now
            bumpNeeded(shopID: items[i].shopId, by: -1)
        }
        struct Body: Encodable { var shopId: String?? ; enum CodingKeys: String, CodingKey { case shopId }
            func encode(to e: Encoder) throws { var c = e.container(keyedBy: CodingKeys.self); if let v = shopId { try c.encode(v, forKey: .shopId) } } }
        do {
            let saved: [ShoppingListItem] = try await api.post("/v1/households/\(hid)/items/checkout", Body(shopId: shopID))
            for s in saved { replace(s) }
        } catch {
            items = before
            self.error = error.localizedDescription
        }
    }

    func move(_ item: ShoppingListItem, toShop shopID: String?) async {
        guard item.shopId != shopID else { return }
        var next = item
        next.shopId = shopID
        if item.status == .needed {
            bumpNeeded(shopID: item.shopId, by: -1)
            bumpNeeded(shopID: shopID, by: 1)
        }
        await patch(item, PatchBody(shopId: .some(shopID)), optimistic: next)
    }

    func edit(_ item: ShoppingListItem, name: String, quantity: String?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let q = quantity?.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = item
        next.name = trimmed
        next.quantity = (q?.isEmpty ?? true) ? nil : q
        await patch(item, PatchBody(name: trimmed, quantity: .some(next.quantity)), optimistic: next)
    }

    /// Removes the item now and deletes it on the server after `grace` unless `undoDelete` is called.
    func delete(_ item: ShoppingListItem, grace: Duration = .seconds(5)) {
        guard let hid else { return }
        items.removeAll { $0.id == item.id }
        if item.status == .needed { bumpNeeded(shopID: item.shopId, by: -1) }
        var pending = PendingDelete(id: item.id, item: item, task: nil)
        pending.task = Task { [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self else { return }
            pendingDeletes.removeAll { $0.id == item.id }
            do {
                try await api.delete("/v1/households/\(hid)/items/\(item.id)")
            } catch {
                self.error = error.localizedDescription
                await refresh()
            }
        }
        pendingDeletes.append(pending)
    }

    func undoDelete(_ id: String) {
        guard let i = pendingDeletes.firstIndex(where: { $0.id == id }) else { return }
        let p = pendingDeletes.remove(at: i)
        p.task?.cancel()
        if !items.contains(where: { $0.id == p.id }) {
            items.append(p.item)
            items.sort { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            if p.item.status == .needed { bumpNeeded(shopID: p.item.shopId, by: 1) }
        }
    }

    var lastPendingDelete: PendingDelete? { pendingDeletes.last }

    func clearBought() async {
        guard let hid else { return }
        let before = items
        items.removeAll { $0.status == .bought }
        do {
            try await api.delete("/v1/households/\(hid)/items?status=bought")
        } catch {
            items = before
            self.error = error.localizedDescription
        }
    }

    // MARK: shops

    @discardableResult
    func addShop(name: String) async -> Shop? {
        guard let hid else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = shops.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return existing }
        do {
            let shop: Shop = try await api.post("/v1/households/\(hid)/shops", ["name": trimmed])
            if !shops.contains(where: { $0.id == shop.id }) { shops.append(shop) }
            return shop
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func renameShop(_ shop: Shop, name: String) async {
        guard let hid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != shop.name else { return }
        do {
            let saved: Shop = try await api.patch("/v1/households/\(hid)/shops/\(shop.id)", ["name": trimmed])
            replaceShop(saved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Deletes the shop; its items become Unsorted (the server sets shop_id NULL).
    func deleteShop(_ shop: Shop) async {
        guard let hid else { return }
        let beforeShops = shops, beforeItems = items
        shops.removeAll { $0.id == shop.id }
        for i in items.indices where items[i].shopId == shop.id { items[i].shopId = nil }
        do {
            try await api.delete("/v1/households/\(hid)/shops/\(shop.id)")
        } catch {
            shops = beforeShops
            items = beforeItems
            self.error = error.localizedDescription
        }
    }

    // MARK: realtime

    /// Applies one change frame; returns true when a refetch is needed (shop deletions move items).
    @discardableResult
    func apply(_ change: ChangeEvent) -> Bool {
        guard let data = try? JSONEncoder().encode(change.row) else { return false }
        switch (change.table, change.type) {
        case ("shopping_list_items", "delete"):
            if let id = change.row["id"]?.stringValue {
                pendingDeletes.removeAll { $0.id == id }
                items.removeAll { $0.id == id }
            }
        case ("shopping_list_items", _):
            if let row = try? JSON.decode(ShoppingListItem.self, from: data) {
                if pendingDeletes.contains(where: { $0.id == row.id }) { return false }
                replace(row)
            }
        case ("shops", "delete"):
            if let id = change.row["id"]?.stringValue {
                shops.removeAll { $0.id == id }
                for i in items.indices where items[i].shopId == id { items[i].shopId = nil }
            }
            return true
        case ("shops", _):
            if let row = try? JSON.decode(Shop.self, from: data) { replaceShop(row) }
        case ("catalog_items", "delete"):
            if let id = change.row["id"]?.stringValue { products.removeAll { $0.id == id } }
        case ("catalog_items", _):
            if let row = try? JSON.decode(CatalogItem.self, from: data) {
                if let i = products.firstIndex(where: { $0.id == row.id }) { products[i] = row } else { products.append(row) }
                products.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        default:
            break
        }
        return false
    }

    static func applied(items: [ShoppingListItem], change: ChangeEvent) -> [ShoppingListItem] {
        let store = ListStore(api: ApiClient { _ in "" })
        store.items = items
        store.loadedHouseholdID = "test"
        store.apply(change)
        return store.items
    }

    // MARK: helpers

    private func replace(_ item: ShoppingListItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
        } else {
            items.append(item)
            items.sort { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        }
    }

    private func replaceShop(_ shop: Shop) {
        if let i = shops.firstIndex(where: { $0.id == shop.id }) {
            shops[i] = shop
        } else {
            shops.append(shop)
        }
        shops.sort { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    private func bumpNeeded(shopID: String?, by delta: Int) {
        guard let shopID, let i = shops.firstIndex(where: { $0.id == shopID }) else { return }
        shops[i].neededCount = max(0, shops[i].neededCount + delta)
    }
}
