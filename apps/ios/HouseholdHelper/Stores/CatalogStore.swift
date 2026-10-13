import Foundation
import Observation

/// Catalog of one shop (shop detail screen).
@Observable
final class CatalogStore {
    let householdID: String
    let shopID: String
    private(set) var items: [CatalogItem] = []
    private(set) var loaded = false
    var error: String?
    private let api: ApiClient

    init(api: ApiClient, householdID: String, shopID: String) {
        self.api = api
        self.householdID = householdID
        self.shopID = shopID
    }

    private var base: String { "/v1/households/\(householdID)/shops/\(shopID)/catalog-items" }

    func load() async {
        do {
            items = try await api.get(base)
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
    }

    func add(name: String, defaultUnit: String? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            var body = ["name": trimmed]
            if let u = defaultUnit?.trimmingCharacters(in: .whitespaces), !u.isEmpty { body["default_unit"] = u }
            let saved: CatalogItem = try await api.post(base, body)
            items.append(saved)
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ item: CatalogItem) async {
        let before = items
        items.removeAll { $0.id == item.id }
        do {
            try await api.delete("\(base)/\(item.id)")
        } catch {
            items = before
            self.error = error.localizedDescription
        }
    }

    func apply(_ change: ChangeEvent) {
        guard change.table == "catalog_items" else { return }
        if change.type == "delete" {
            if let id = change.row["id"]?.stringValue { items.removeAll { $0.id == id } }
            return
        }
        guard let data = try? JSONEncoder().encode(change.row), let row = try? JSON.decode(CatalogItem.self, from: data), row.shopId == shopID else { return }
        if let i = items.firstIndex(where: { $0.id == row.id }) { items[i] = row } else { items.append(row) }
        items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
