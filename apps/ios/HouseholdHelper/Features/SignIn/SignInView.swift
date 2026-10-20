import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.55, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Brand.primaryDeep, Brand.primary, Brand.shopPalette[3],
                    Brand.primary, Brand.mint.opacity(0.9), Brand.primary,
                    Brand.shopPalette[2], Brand.primary, Brand.primaryDeep,
                ])
                .ignoresSafeArea()
                VStack(spacing: 18) {
                    // The mark on its dark tile; the rings echo its orbit.
                    ZStack {
                        Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1.5).frame(width: 420, height: 420)
                        Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1.5).frame(width: 300, height: 300)
                        BrandMark(style: .darkTile)
                            .frame(width: 124, height: 124)
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 14)
                    }
                    .frame(width: 124, height: 124)
                    Text("Household Helper")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("One shopping list for the whole home.\nAdd it when it runs out. Tick it in the aisle.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
            }
            .frame(maxHeight: .infinity)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
            .ignoresSafeArea(edges: .top)
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
