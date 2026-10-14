import SwiftUI

@main
struct HouseholdHelperApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth: AuthStore
    @State private var households: HouseholdStore
    @State private var list: ListStore
    @State private var events: EventsClient
    @State private var router: AppRouter
    private let api: ApiClient

    init() {
        FirebaseSetup.configure()
        let auth = AuthStore()
        let api = ApiClient { force in try await auth.idToken(forceRefresh: force) }
        let households = HouseholdStore(api: api)
        let router = AppRouter()
        self.api = api
        _auth = State(initialValue: auth)
        _households = State(initialValue: households)
        _list = State(initialValue: ListStore(api: api))
        _events = State(initialValue: EventsClient { force in try await auth.idToken(forceRefresh: force) })
        _router = State(initialValue: router)
        PushRegistrar.shared.attach(api: api, households: households, router: router)
        auth.beforeSignOut = { await PushRegistrar.shared.unregister() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(households)
                .environment(list)
                .environment(events)
                .environment(router)
                .environment(\.api, api)
        }
    }
}

private struct ApiKey: EnvironmentKey {
    static let defaultValue = ApiClient { _ in "" }
}

extension EnvironmentValues {
    var api: ApiClient {
        get { self[ApiKey.self] }
        set { self[ApiKey.self] = newValue }
    }
}
