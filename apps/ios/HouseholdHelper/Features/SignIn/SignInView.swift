import AuthenticationServices
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
                // Apple first: App Store 4.8 requires it alongside any third-party login.
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await completeApple(result) }
                }
                .signInWithAppleButtonStyle(appleStyle)
                .frame(height: 50)
                .clipShape(Capsule())
                .disabled(busy || Env.isEmulatorBuild)
                .opacity(Env.isEmulatorBuild ? 0.35 : 1) // the Apple button does not dim itself when disabled
                .accessibilityIdentifier(A11y.signInApple)

                Button {
                    Task { await signInGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle")
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.glassProminent)
                .disabled(busy || Env.isEmulatorBuild)
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
                Text("Dev build: Firebase Auth emulator (Apple and Google need the Firebase scheme)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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

    @Environment(\.colorScheme) private var colorScheme
    private var appleStyle: SignInWithAppleButton.Style { colorScheme == .dark ? .white : .black }

    private func signInGoogle() async {
        busy = true
        defer { busy = false }
        do {
            try await auth.signInWithGoogle()
        } catch SignInError.cancelled {
            // user backed out: no message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func completeApple(_ result: Result<ASAuthorization, any Error>) async {
        busy = true
        defer { busy = false }
        do {
            try await auth.completeAppleSignIn(result)
        } catch SignInError.cancelled {
        } catch {
            self.error = error.localizedDescription
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
