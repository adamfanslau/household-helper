// Tab selection, navigation paths and deep links: householdhelper://list | shops | shops/<id> | settings | join/<CODE>
import Foundation
import Observation
import SwiftUI

@Observable
final class AppRouter {
    enum Tab: String, Hashable { case list, shops, settings }

    var tab: Tab = .list
    var shopsPath = NavigationPath()
    /// Set by a join/<CODE> link; the onboarding or settings join sheet consumes it.
    var pendingJoinCode: String?
    var showJoinSheet = false

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "householdhelper" else { return false }
        let parts = ([url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" })
        switch parts.first {
        case "list":
            tab = .list
        case "shops":
            tab = .shops
            shopsPath = NavigationPath()
            if parts.count > 1 { shopsPath.append(parts[1]) } // shop id; ShopsView resolves it
        case "settings":
            tab = .settings
        case "join":
            guard parts.count > 1 else { return false }
            pendingJoinCode = parts[1].uppercased()
            showJoinSheet = true
        default:
            return false
        }
        return true
    }
}
