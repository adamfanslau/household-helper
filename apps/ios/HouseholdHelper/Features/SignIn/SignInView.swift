import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Household Helper")
                .font(.largeTitle.bold())
            Text("One shopping list for the whole home.")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    // Google sign-in lands in iOS step I3 (needs the real Firebase project).
                } label: {
                    Label("Continue with Google", systemImage: "g.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(true)
                .accessibilityIdentifier(A11y.signInGoogle)

                #if HH_EMULATOR
                HStack(spacing: 12) {
                    ForEach(["alice", "bob"], id: \.self) { who in
                        Button("Sign in as \(who.capitalized)") {
                            Task { await signIn(who) }
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier(A11y.signInDev(who))
                    }
                }
                .disabled(busy)
                Text("Dev build: Firebase Auth emulator")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .task {
            #if HH_EMULATOR
            // RootView handles HH_UITEST_USER when a session already exists; this covers the signed-out start.
            if let who = Env.uiTestUser, auth.user == nil { await signIn(who) }
            #endif
        }
    }

    #if HH_EMULATOR
    private func signIn(_ who: String) async {
        busy = true
        defer { busy = false }
        do {
            try await auth.signInDev(who)
        } catch {
            self.error = error.localizedDescription
        }
    }
    #endif
}
