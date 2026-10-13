import OSLog
import Foundation
import Observation

@Observable
final class ListStore {
    private(set) var items: [ShoppingListItem] = []
    private(set) var shops: [Shop] = []
    private(set) var loading = false
    private(set) var loadedHouseholdID: String?
    var error: String?

    private let api: ApiClient

    init(api: ApiClient) {
        self.api = api
    }

    var sections: ListGrouping.Sections {
        ListGrouping.sections(items: items, shops: shops)
    }

    func load(householdID: String) async {
        loading = loadedHouseholdID != householdID
        defer { loading = false }
        do {
            async let i: [ShoppingListItem] = api.get("/v1/households/\(householdID)/items")
            async let s: [Shop] = api.get("/v1/households/\(householdID)/shops")
            (items, shops) = try await (i, s)
            loadedHouseholdID = householdID
            error = nil
            Log.api.info("list loaded: \(self.items.count) items, \(self.shops.count) shops")
        } catch {
            self.error = error.localizedDescription
            Log.api.error("list load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        items = []
        shops = []
        loadedHouseholdID = nil
    }
}
