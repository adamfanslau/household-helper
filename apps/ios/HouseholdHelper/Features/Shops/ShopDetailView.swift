import SwiftUI

/// One shop while shopping: what is still needed there (tap = bought), plus rename/delete.
struct ShopDetailView: View {
    @Environment(ListStore.self) private var list
    @Environment(\.dismiss) private var dismiss
    let shopID: String
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var toggleTick = 0
    @State private var checkoutTick = 0

    private var shop: Shop? { list.shop(shopID) }
    /// Still to find first, ticked (in the basket) last.
    private var needed: [ShoppingListItem] {
        let open = list.items.filter { $0.shopId == shopID && $0.status != .bought }
        return open.filter { $0.status == .needed } + open.filter { $0.status == .inBasket }
    }
    private var basketCount: Int { needed.filter { $0.status == .inBasket }.count }

    var body: some View {
        Group {
            if needed.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to buy here", systemImage: "basket")
                } description: {
                    Text("Items you add for \(shop?.name ?? "this shop") show up here.")
                }
            } else {
                List {
                    ForEach(needed) { item in
                        // Default button style: the only kind of row synthetic taps reach (see ListView).
                        Button {
                            toggleTick += 1
                            Task { await list.toggle(item) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.status == .inBasket ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.status == .inBasket ? Color.green : Color.secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).foregroundStyle(.primary)
                                    if let qty = item.quantity, !qty.isEmpty {
                                        Text(qty).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier(A11y.shopRow(item.name))
                        .accessibilityLabel("\(item.name)\(item.quantity.map { ", \($0)" } ?? ""), \(item.status == .inBasket ? "in basket" : "needed")")
                    }
                }
                .listStyle(.insetGrouped)
                .animation(.snappy, value: needed)
                .refreshable { await list.refresh() }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if basketCount > 0 {
                Button {
                    checkoutTick += 1
                    Task { await list.checkout(shopID: .some(shopID)) }
                } label: {
                    Label("Checkout · \(basketCount) in the basket", systemImage: "cart.badge.checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier(A11y.shopCheckout)
            }
        }
        .navigationTitle(shop?.name ?? "Shop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") { newName = shop?.name ?? ""; renaming = true }
                    Button("Delete shop", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier(A11y.shopMenu)
            }
        }
        .alert("Rename shop", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { if let shop { Task { await list.renameShop(shop, name: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(shop?.name ?? "shop")?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let shop {
                    Task { await list.deleteShop(shop) }
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items on the list move to Unsorted; your products keep their history.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: toggleTick)
        .sensoryFeedback(.success, trigger: checkoutTick)
    }
}
