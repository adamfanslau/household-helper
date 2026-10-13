import Foundation
import OSLog
import Observation

/// Items and shops of the selected household with optimistic mutations, delayed deletes
/// with undo, and SSE change application.
@Observable
final class ListStore {
    private(set) var items: [ShoppingListItem] = []
    private(set) var shops: [Shop] = []
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

    // MARK: loading

    func load(householdID: String) async {
        loading = loadedHouseholdID != householdID
        defer { loading = false }
        do {
            async let i: [ShoppingListItem] = api.get("/v1/households/\(householdID)/items")
            async let s: [Shop] = api.get("/v1/households/\(householdID)/shops")
            let (loadedItems, loadedShops) = try await (i, s)
            let hidden = Set(pendingDeletes.map(\.id))
            items = loadedItems.filter { !hidden.contains($0.id) }
            shops = loadedShops
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
        loadedHouseholdID = nil
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

    func toggle(_ item: ShoppingListItem) async {
        Log.ui.info("toggle \(item.name, privacy: .public) hid=\(self.hid ?? "nil", privacy: .public)")
        var next = item
        next.status = item.status == .needed ? .bought : .needed
        next.boughtAt = next.status == .bought ? Date() : nil
        bumpNeeded(shopID: item.shopId, by: next.status == .bought ? -1 : 1)
        await patch(item, PatchBody(status: next.status), optimistic: next)
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

    func addShop(name: String) async {
        guard let hid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let shop: Shop = try await api.post("/v1/households/\(hid)/shops", ["name": trimmed])
            if !shops.contains(where: { $0.id == shop.id }) { shops.append(shop) }
        } catch {
            self.error = error.localizedDescription
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
