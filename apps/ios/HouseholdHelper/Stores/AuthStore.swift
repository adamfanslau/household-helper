import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import OSLog
import Observation
import UIKit

@Observable
final class AuthStore {
    private(set) var user: User?
    private(set) var ready = false
    private var handle: AuthStateDidChangeListenerHandle?
    /// Runs while the ID token still works (push token removal).
    var beforeSignOut: (() async -> Void)?

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

    // MARK: Google

    /// GIDSignIn → Firebase credential. Needs the real project (client id from GoogleService-Info.plist).
    func signInWithGoogle() async throws {
        #if HH_EMULATOR
        throw SignInError.unavailableInDevBuild
        #else
        guard let clientID = FirebaseApp.app()?.options.clientID else { throw SignInError.unavailableInDevBuild }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = Self.presenter() else { throw SignInError.noPresenter }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw SignInError.noIdentityToken }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
        try await Auth.auth().signIn(with: credential)
        Log.auth.info("google sign-in ok")
        #endif
    }

    /// Google's OAuth callback (REVERSED_CLIENT_ID URL scheme).
    @discardableResult
    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func presenter() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    // MARK: Apple

    /// Raw nonce for the current Sign in with Apple request; its SHA-256 goes to Apple.
    private(set) var appleNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.random()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256Hex(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, any Error>) async throws {
        switch result {
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled { throw SignInError.cancelled }
            throw error
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else { throw SignInError.noIdentityToken }
            let firebaseCredential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: credential.fullName)
            try await Auth.auth().signIn(with: firebaseCredential)
            appleNonce = nil
            Log.auth.info("apple sign-in ok")
        }
    }

    func signOut() async {
        await beforeSignOut?()
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }
}
