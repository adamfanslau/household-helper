import OSLog
import Foundation
import Observation

@Observable
final class HouseholdStore {
    private(set) var households: [Household] = []
    private(set) var current: Household?
    private(set) var loaded = false
    var error: String?

    private let api: ApiClient
    private let defaults: UserDefaults
    private static let currentKey = "currentHouseholdID"

    init(api: ApiClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    /// Loads the caller's households and restores the last selection (the Expo app forgot it on relaunch).
    func load() async {
        do {
            let list: [Household] = try await api.get("/v1/households")
            households = list
            let saved = defaults.string(forKey: Self.currentKey)
            current = list.first { $0.id == saved } ?? list.first { $0.id == current?.id } ?? list.first
            loaded = true
            error = nil
            Log.api.info("households loaded: \(list.count) current=\(self.current?.id ?? "none", privacy: .public)")
        } catch {
            self.error = error.localizedDescription
            loaded = true
            Log.api.error("households load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func select(_ h: Household) {
        current = h
        defaults.set(h.id, forKey: Self.currentKey)
        Log.ui.info("selected household \(h.id, privacy: .public)")
    }

    @discardableResult
    func create(name: String) async throws -> Household {
        let h: Household = try await api.post("/v1/households", ["name": name])
        await load()
        select(h)
        return h
    }

    /// Joins and selects the household (the Expo app stayed on the old one).
    @discardableResult
    func join(code: String) async throws -> Household {
        let h: Household = try await api.post("/v1/households/join", ["code": code])
        await load()
        select(h)
        return h
    }

    func reset() {
        households = []
        current = nil
        loaded = false
        error = nil
    }
}
