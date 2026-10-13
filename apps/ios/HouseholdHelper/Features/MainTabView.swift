import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("List", systemImage: "checklist") {
                ListView()
            }
            .accessibilityIdentifier(A11y.tabList)
            Tab("Shops", systemImage: "storefront") {
                NavigationStack {
                    ContentUnavailableView("Shops arrive in the next step", systemImage: "storefront")
                        .navigationTitle("Shops")
                }
            }
            .accessibilityIdentifier(A11y.tabShops)
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
            .accessibilityIdentifier(A11y.tabSettings)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
