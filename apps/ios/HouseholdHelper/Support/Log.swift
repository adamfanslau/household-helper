// os_log channel for the app. Visible with `scripts/dev/ios.sh log <udid>` (subsystem filter).
// Never log tokens, sessions or full Authorization headers.
import OSLog

nonisolated enum Log {
    static let subsystem = "com.householdhelper.app"
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
