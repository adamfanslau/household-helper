// Build-time configuration, baked into Info.plist by Config/*.xcconfig so a home-screen relaunch
// behaves like a launch from Xcode. The only runtime input is HH_UITEST_USER (dev builds).
import Foundation

nonisolated enum Env {
    static let apiBaseURL: URL = {
        let s = Bundle.main.object(forInfoDictionaryKey: "HHApiBaseURL") as? String ?? ""
        return URL(string: s.isEmpty ? "http://localhost:8091" : s)!
    }()

    /// host:port of the Firebase Auth emulator, or nil for the real project.
    static let authEmulatorHost: String? = {
        let s = Bundle.main.object(forInfoDictionaryKey: "HHAuthEmulatorHost") as? String ?? ""
        return s.isEmpty ? nil : s
    }()

    static let isEmulatorBuild: Bool = {
        #if HH_EMULATOR
        true
        #else
        false
        #endif
    }()

    /// `alice` | `bob`: auto sign-in for simulator runs driven by scripts/dev/ios.sh (dev builds only).
    static var uiTestUser: String? {
        guard isEmulatorBuild, let u = ProcessInfo.processInfo.environment["HH_UITEST_USER"], !u.isEmpty else { return nil }
        return u
    }
}
