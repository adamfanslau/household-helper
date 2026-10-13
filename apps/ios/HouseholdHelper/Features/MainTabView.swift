import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(EventsClient.self) private var events

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("List", systemImage: "checklist", value: AppRouter.Tab.list) {
                ListView()
            }
            Tab("Shops", systemImage: "storefront", value: AppRouter.Tab.shops) {
                ShopsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppRouter.Tab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .top) {
            ConnectionPill()
        }
        .sheet(isPresented: $router.showJoinSheet) {
            OnboardingView(isSheet: true, initialMode: .join, initialCode: router.pendingJoinCode)
        }
    }
}

/// "Reconnecting…" after 3 s without a stream; hidden as soon as `ready` arrives.
struct ConnectionPill: View {
    @Environment(EventsClient.self) private var events
    @State private var tick = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if events.showsReconnecting {
                Label("Reconnecting…", systemImage: "wifi.exclamationmark")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect()
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("connection.reconnecting")
            }
        }
        .animation(.snappy, value: events.showsReconnecting)
    }
}
