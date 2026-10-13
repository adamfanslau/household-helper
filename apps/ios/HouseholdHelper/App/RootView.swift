import SwiftUI

/// Gate: signed out → SignIn; no household → Onboarding; else the tabs.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list

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
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .onChange(of: auth.uid) { _, uid in
            households.reset()
            list.clear()
            if uid != nil {
                Task { await households.load() }
            }
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
}
