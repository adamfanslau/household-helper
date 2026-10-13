import FirebaseAuth
import FirebaseCore

enum FirebaseSetup {
    static func configure() {
        #if HH_EMULATOR
        // Dev builds never ship a GoogleService-Info.plist; these values are fabricated and the
        // Auth emulator accepts any API key. Must run before the first Auth.auth() use.
        let options = FirebaseOptions(googleAppID: "1:123456789012:ios:0123456789abcdef", gcmSenderID: "123456789012")
        options.projectID = "demo-household-helper"
        options.apiKey = "demo-api-key"
        FirebaseApp.configure(options: options)
        if let host = Env.authEmulatorHost {
            let parts = host.split(separator: ":")
            Auth.auth().useEmulator(withHost: String(parts.first ?? "127.0.0.1"), port: Int(parts.last ?? "9099") ?? 9099)
        }
        #else
        FirebaseApp.configure()
        #endif
    }
}
