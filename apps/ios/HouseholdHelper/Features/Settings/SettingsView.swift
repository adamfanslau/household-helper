import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HouseholdStore.self) private var households
    @Environment(AppRouter.self) private var router
    @State private var showOnboarding = false
    @State private var confirmSignOut = false
    @State private var renaming = false
    @State private var newName = ""
    private let push = PushRegistrar.shared

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // The home card: this household, and who you are in it.
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "house.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(households.current?.name ?? "—")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .accessibilityIdentifier(A11y.settingsName)
                            Text("Signed in as \(auth.email ?? "—")")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Menu {
                            Button("Rename household", systemImage: "pencil") { newName = households.current?.name ?? ""; renaming = true }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .accessibilityIdentifier(A11y.settingsMenu)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Brand.gradient)
                }
                Section {
                    if let code = households.currentCode {
                        Text(code)
                            .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                            .kerning(4)
                            .frame(maxWidth: .infinity)
                            .textSelection(.enabled)
                            .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")
                            .accessibilityIdentifier(A11y.settingsInviteCode)
                        ShareLink(item: inviteMessage(code: code, household: households.current?.name ?? "")) {
                            Label("Share invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier(A11y.settingsShare)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Button("Regenerate code", systemImage: "arrow.clockwise") {
                        Task { await households.regenerateInvite() }
                    }
                    .accessibilityIdentifier(A11y.settingsRegenerate)
                } header: {
                    Text("Invite code")
                } footer: {
                    Text("Share this so others can join and see the same list.")
                }
                if households.households.count > 1 {
                    Section("Switch household") {
                        ForEach(households.households) { h in
                            Button {
                                households.select(h)
                            } label: {
                                HStack {
                                    Text(h.name).foregroundStyle(.primary)
                                    Spacer()
                                    if h.id == households.current?.id {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .tint(.primary)
                            .accessibilityIdentifier(A11y.settingsHousehold(h.name))
                        }
                    }
                }
                Section {
                    Button("Create or join another household", systemImage: "plus") { showOnboarding = true }
                        .accessibilityIdentifier(A11y.settingsAddHousehold)
                }
                Section {
                    switch push.status {
                    case .authorized:
                        LabeledContent("Notifications", value: "On")
                    case .denied:
                        Button("Notifications are off — open Settings", systemImage: "bell.slash") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    case .notAsked, .unknown:
                        Button("Enable notifications", systemImage: "bell") { Task { await push.requestAuthorization() } }
                    }
                } footer: {
                    Text("Hear when someone adds to the list or joins.")
                }
                .accessibilityIdentifier(A11y.settingsNotifications)
                Section {
                    LabeledContent("Version", value: version)
                    LabeledContent("Server", value: Env.apiBaseURL.host() ?? "")
                } header: {
                    Text("About")
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(A11y.settingsSignOut)
                }
            }
            .navigationTitle("Household")
            .task(id: households.current?.id) { await households.loadInvites() }
            .task { await push.refreshStatus() }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isSheet: true)
            }
            .alert("Rename household", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Save") { Task { await households.rename(name: newName) } }
                Button("Cancel", role: .cancel) {}
            }
            // An alert, not a confirmationDialog: iOS 26 shows dialogs from Form rows as popovers.
            .alert("Sign out of Household Helper?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your lists stay in the household; sign back in any time.")
            }
        }
    }
}
