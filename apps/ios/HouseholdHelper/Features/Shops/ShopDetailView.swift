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
    private var toFind: [ShoppingListItem] { needed.filter { $0.status == .needed } }
    private var inBasket: [ShoppingListItem] { needed.filter { $0.status == .inBasket } }

    private var progressText: String {
        if needed.isEmpty { return "All done here" }
        if basketCount == 0 { return "\(needed.count) to buy" }
        return "\(basketCount) of \(needed.count) in the basket · \(toFind.count) left to find"
    }

    /// Shop identity + progress ring, shown above the aisle list.
    private var header: some View {
        let color = Brand.shopColor(shop?.name ?? "")
        return HStack(spacing: 16) {
            ShopGlyph(name: shop?.name, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(shop?.name ?? "Shop").font(.title2.bold())
                Text(progressText)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: needed.isEmpty ? 1 : Double(basketCount) / Double(needed.count))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: basketCount)
                Text(needed.isEmpty ? "✓" : "\(basketCount)/\(needed.count)").font(.caption.weight(.bold)).monospacedDigit()
            }
            .frame(width: 52, height: 52)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// One product in the aisle. Default button style: the only kind of row synthetic taps reach (see ListView).
    private func aisleRow(_ item: ShoppingListItem) -> some View {
        Button {
            toggleTick += 1
            Task { await list.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                CheckMark(status: item.status, tint: Brand.shopColor(shop?.name ?? ""))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).foregroundStyle(item.status == .inBasket ? .secondary : .primary)
                    if let qty = item.quantity, !qty.isEmpty {
                        Chip(text: qty, tint: Brand.shopColor(shop?.name ?? ""))
                    }
                }
                Spacer()
                if item.status == .needed {
                    Text("Tap to tick").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .tint(.primary)
        .accessibilityIdentifier(A11y.shopRow(item.name))
        .accessibilityLabel("\(item.name)\(item.quantity.map { ", \($0)" } ?? ""), \(item.status == .inBasket ? "in basket" : "needed")")
    }

    var body: some View {
        Group {
            if needed.isEmpty {
                ScrollView {
                    VStack(spacing: 24) {
                        header
                        EmptyState(symbol: Brand.shopSymbol(shop?.name ?? ""), title: "Nothing to buy here", text: "Items you add for \(shop?.name ?? "this shop") show up here, ready to tick off in the aisle.")
                    }
                    .padding(.top, 8)
                }
            } else {
                List {
                    Section {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    // The aisle is two piles: what is still to find on top, what is already in the basket below.
                    if !toFind.isEmpty {
                        Section {
                            ForEach(toFind) { item in aisleRow(item) }
                        } header: {
                            Text("Still to find")
                        }
                    }
                    if !inBasket.isEmpty {
                        Section {
                            ForEach(inBasket) { item in aisleRow(item) }
                        } header: {
                            Text("In the basket")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .animation(.snappy, value: needed)
                .refreshable { await list.refresh() }
            }
        }
        .background { ScreenGround(tint: Brand.shopColor(shop?.name ?? ""), strength: 0.42) }
        .safeAreaBar(edge: .bottom) {
            if basketCount > 0 {
                Button {
                    checkoutTick += 1
                    Task { await list.checkout(shopID: .some(shopID)) }
                } label: {
                    Label("Checkout · \(basketCount) in the basket", systemImage: "cart.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.basket)
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
