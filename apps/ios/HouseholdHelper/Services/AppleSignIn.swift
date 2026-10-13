// Sign in with Apple nonce handling: a random nonce is sent to Apple as its SHA-256 hex digest and
// the raw nonce to Firebase, which verifies the id token carries the digest.
import AuthenticationServices
import CryptoKit
import Foundation

nonisolated enum AppleNonce {
    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum SignInError: LocalizedError, Sendable {
    case cancelled
    case noIdentityToken
    case noPresenter
    case unavailableInDevBuild

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .noIdentityToken: "Apple did not return an identity token."
        case .noPresenter: "No window to present sign-in from."
        case .unavailableInDevBuild: "Google sign-in needs the real Firebase project (not the emulator build)."
        }
    }
}
