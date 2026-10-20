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
                    ScrollView {
                        EmptyState(symbol: "storefront.fill", title: "No shops yet", text: "Add the places you shop. Items you add for a shop are grouped under it, with a count of what is left to buy.")
                            .padding(.top, 60)
                    }
                } else {
                    List {
                        ForEach(list.shopsByActivity) { shop in
                            let open = list.openCount(for: shop.id)
                            let basket = list.items.filter { $0.shopId == shop.id && $0.status == .inBasket }.count
                            NavigationLink(value: shop.id) {
                                HStack(spacing: 14) {
                                    ShopGlyph(name: shop.name, size: 44)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(shop.name).font(.headline)
                                        if open > 0 {
                                            Text(basket > 0 ? "\(basket) of \(open) in the basket" : "\(open) to buy")
                                                .font(.caption).foregroundStyle(.secondary)
                                            ProgressCapsule(value: Double(basket) / Double(max(1, open)), tint: Brand.shopColor(shop.name))
                                        } else {
                                            Text("Nothing to buy").font(.caption).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    if open > 0 {
                                        Text("\(open)")
                                            .font(.subheadline.weight(.bold))
                                            .monospacedDigit()
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 4)
                                            .background(Brand.shopColor(shop.name).opacity(0.16), in: Capsule())
                                            .foregroundStyle(Brand.shopColor(shop.name))
                                            .accessibilityIdentifier(A11y.shopsCount(shop.name))
                                    }
                                }
                                .padding(.vertical, 4)
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
                        Section {
                            HStack(spacing: 14) {
                                SparkGlyph(size: 22, tint: Brand.mintBright)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Shopping order follows you").font(.subheadline.weight(.semibold))
                                    Text("Shops with the most left to buy rise to the top, so the next errand is always first.")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.78))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 6)
                            .listRowBackground(Brand.inkGradient)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .animation(.snappy, value: list.shopsByActivity)
                    .refreshable { await list.refresh() }
                }
            }
            .background { ScreenGround() }
            .navigationTitle("Shops")
            .navigationSubtitle(list.shops.isEmpty ? "" : "Most to buy first")
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
