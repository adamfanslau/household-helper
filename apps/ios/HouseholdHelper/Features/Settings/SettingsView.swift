import SwiftUI

/// Step I1 subset: household, account, switch household, sign out. Invite + share come in I2.
struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(HouseholdStore.self) private var households

    var body: some View {
        NavigationStack {
            Form {
                Section("Household") {
                    LabeledContent("Name", value: households.current?.name ?? "—")
                    LabeledContent("Signed in as", value: auth.email ?? "—")
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
                            .accessibilityIdentifier(A11y.settingsHousehold(h.name))
                        }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(A11y.settingsSignOut)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
