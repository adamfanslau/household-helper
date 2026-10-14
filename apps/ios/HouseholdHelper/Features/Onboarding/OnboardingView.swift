import SwiftUI

/// Create or join a household. Full screen on first run, a sheet from Settings or a join link.
struct OnboardingView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case create, join
        var id: String { rawValue }
        var title: String { self == .create ? "Create" : "Join" }
    }

    @Environment(AuthStore.self) private var auth
    @Environment(HouseholdStore.self) private var households
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    var isSheet: Bool
    var initialMode: Mode = .create
    var initialCode: String? = nil
    @State private var mode: Mode = .create
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(A11y.onboardingMode)
                    TextField(mode == .create ? "Household name" : "Invite code (e.g. AB12CD34)", text: $input)
                        .textInputAutocapitalization(mode == .join ? .characters : .words)
                        .autocorrectionDisabled(mode == .join)
                        .font(mode == .join ? .system(.body, design: .monospaced) : .body)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .accessibilityIdentifier(A11y.onboardingInput)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(mode == .create ? "Start a household and invite others with its code." : "Enter the 8-character code from a household member.")
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if busy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(mode == .create ? "Create household" : "Join household").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier(A11y.onboardingSubmit)
                }
            }
            .navigationTitle(isSheet ? "Another household" : "Welcome")
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign out") { Task { await auth.signOut() } }
                            .accessibilityIdentifier(A11y.settingsSignOut)
                    }
                }
            }
            .onAppear {
                mode = initialMode
                if let code = initialCode { input = code; mode = .join }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            switch mode {
            case .create: try await households.create(name: value)
            case .join: try await households.join(code: value.uppercased())
            }
            input = ""
            error = nil
            router.pendingJoinCode = nil
            router.tab = .list
            if isSheet { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
