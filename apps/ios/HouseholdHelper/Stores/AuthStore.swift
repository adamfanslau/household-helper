import OSLog
import FirebaseAuth
import Observation

@Observable
final class AuthStore {
    private(set) var user: User?
    private(set) var ready = false
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            MainActor.assumeIsolated {
                self.user = user
                self.ready = true
                Log.auth.info("auth state: \(user?.uid ?? "signed out", privacy: .public)")
            }
        }
    }

    var uid: String? { user?.uid }
    var email: String? { user?.email }

    /// Firebase caches the token and refreshes it near expiry; forceRefresh handles a server 401.
    func idToken(forceRefresh: Bool = false) async throws -> String {
        guard let user else { throw ApiError.unauthenticated }
        // Completion form: the non-Sendable User stays on the main actor.
        return try await withCheckedThrowingContinuation { cont in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let token {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: error ?? ApiError.unauthenticated)
                }
            }
        }
    }

    #if HH_EMULATOR
    func signInDev(_ who: String) async throws {
        try await Auth.auth().signIn(withEmail: "\(who)@dev.local", password: "password")
    }
    #endif

    func signOut() {
        try? Auth.auth().signOut()
    }
}
