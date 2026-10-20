import SwiftUI

struct ShopsView: View {
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @Environment(AppRouter.self) private var router
    @State private var draft = ""
    @State private var pendingDelete: Shop?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.shopsPath) {
            Group {
                if list.shops.isEmpty {
                    ContentUnavailableView {
                        Label("No shops yet", systemImage: "storefront")
                    } description: {
                        Text("Add the places you shop; items can then be grouped by shop.")
                    }
                } else {
                    List {
                        ForEach(list.shopsByActivity) { shop in
                            let open = list.openCount(for: shop.id)
                            NavigationLink(value: shop.id) {
                                HStack {
                                    Label {
                                        Text(shop.name)
                                    } icon: {
                                        Image(systemName: "storefront")
                                    }
                                    Spacer()
                                    if open > 0 {
                                        Text("\(open)")
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityIdentifier(A11y.shopsCount(shop.name))
                                    }
                                }
                            }
                            .accessibilityIdentifier(A11y.shopsRow(shop.name))
                            .accessibilityLabel("\(shop.name), \(open) to buy")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = shop
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .animation(.snappy, value: list.shopsByActivity)
                    .refreshable { await list.refresh() }
                }
            }
            .navigationTitle("Shops")
            .navigationDestination(for: String.self) { shopID in
                ShopDetailView(shopID: shopID)
            }
            .safeAreaBar(edge: .bottom) {
                HStack(spacing: 10) {
                    TextField("Add a shop", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier(A11y.shopsInput)
                    Button(action: add) {
                        Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add shop")
                    .accessibilityIdentifier(A11y.shopsAdd)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .alert("Delete \(pendingDelete?.name ?? "shop")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let shop = pendingDelete { Task { await list.deleteShop(shop) } }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Its catalog is removed. Items on the list move to Unsorted.")
            }
        }
    }

    private func add() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        draft = ""
        Task { await list.addShop(name: name) }
    }
}
