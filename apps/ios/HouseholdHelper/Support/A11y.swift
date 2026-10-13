// Accessibility identifiers: the shared vocabulary with Android's testTags. AXe taps by these.
import Foundation

nonisolated enum A11y {
    static let signInGoogle = "signin.google"
    static let signInApple = "signin.apple"
    static func signInDev(_ who: String) -> String { "signin.dev.\(who)" }

    static let onboardingMode = "onboarding.mode"
    static let onboardingModeCreate = "onboarding.mode.create"
    static let onboardingModeJoin = "onboarding.mode.join"
    static let onboardingInput = "onboarding.input"
    static let onboardingSubmit = "onboarding.submit"

    static let tabList = "tab.list"
    static let tabShops = "tab.shops"
    static let tabSettings = "tab.settings"

    static let listInput = "list.input"
    static let listAdd = "list.add"
    static func listItem(_ name: String) -> String { "list.item.\(name)" }
    static let listBoughtToggle = "list.bought.toggle"

    static let shopsInput = "shops.input"
    static let shopsAdd = "shops.add"
    static func shopsRow(_ name: String) -> String { "shops.row.\(name)" }
    static let shopInput = "shop.input"
    static func shopRow(_ name: String) -> String { "shop.row.\(name)" }
    static func shopToList(_ name: String) -> String { "shop.toList.\(name)" }

    static let settingsInviteCode = "settings.inviteCode"
    static let settingsShare = "settings.share"
    static let settingsSignOut = "settings.signOut"
    static func settingsHousehold(_ name: String) -> String { "settings.household.\(name)" }
}
