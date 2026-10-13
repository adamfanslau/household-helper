import SwiftUI

/// Gate: signed out → SignIn; no household → Onboarding; else the tabs. Owns the realtime
/// connection and the foreground/background lifecycle for the selected household.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @Environment(EventsClient.self) private var events
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !auth.ready {
                ProgressView()
            } else if auth.user == nil {
                SignInView()
            } else if !households.loaded {
                ProgressView("Loading…")
                    .task { await households.load() }
            } else if households.current == nil {
                OnboardingView(isSheet: false)
            } else {
                MainTabView()
            }
        }
        .onChange(of: auth.uid) { _, uid in
            events.disconnect()
            households.reset()
            list.clear()
            if uid != nil {
                Task { await households.load() }
            }
        }
        .onChange(of: households.current?.id, initial: true) { _, hid in
            list.clear()
            guard let hid else { events.disconnect(); return }
            wire()
            events.connect(householdID: hid)
        }
        .onChange(of: scenePhase) { _, phase in
            guard let hid = households.current?.id else { return }
            switch phase {
            case .background:
                events.disconnect()
            case .active:
                wire()
                events.connect(householdID: hid)
                Task { await list.load(householdID: hid) }
            default:
                break
            }
        }
        .onOpenURL { url in
            _ = router.handle(url)
        }
        .task(id: auth.ready) {
            #if HH_EMULATOR
            // Script-driven launches: make sure exactly the requested dev user is signed in,
            // even when another dev user's session survived from the previous launch.
            guard auth.ready, let who = Env.uiTestUser else { return }
            if auth.email != "\(who)@dev.local" {
                if auth.user != nil { auth.signOut() }
                try? await auth.signInDev(who)
            }
            #endif
        }
    }

    private func wire() {
        events.onReady = { [list, households] in
            guard let hid = households.current?.id else { return }
            await list.load(householdID: hid)
        }
        events.onChange = { [list, households] change in
            if change.table == "households", let data = try? JSONEncoder().encode(change.row),
               let h = try? JSON.decode(Household.self, from: data) {
                households.apply(h)
                return
            }
            if list.apply(change) {
                Task { await list.refresh() }
            }
        }
    }
}
