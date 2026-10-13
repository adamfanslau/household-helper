import SwiftUI

@main
struct HouseholdHelperApp: App {
    @State private var auth: AuthStore
    @State private var households: HouseholdStore
    @State private var list: ListStore

    init() {
        FirebaseSetup.configure()
        let auth = AuthStore()
        let api = ApiClient { force in try await auth.idToken(forceRefresh: force) }
        _auth = State(initialValue: auth)
        _households = State(initialValue: HouseholdStore(api: api))
        _list = State(initialValue: ListStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(households)
                .environment(list)
        }
    }
}
