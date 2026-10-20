import SwiftUI

/// The home screen: needed items grouped by shop, Unsorted last, "Recently bought" collapsible,
/// a floating + that opens the add sheet, swipe + context-menu actions, undo on delete.
struct ListView: View {
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @State private var showBought = false
    @State private var showAdd = false
    @State private var editing: ShoppingListItem?
    @State private var toggleTick = 0
    @State private var deleteTick = 0
    @State private var checkoutTick = 0

    var body: some View {
        NavigationStack {
            Group {
                if let household = households.current {
                    content(for: household)
                        .task(id: household.id) { await list.load(householdID: household.id) }
                } else {
                    ContentUnavailableView("No household", systemImage: "house")
                }
            }
            .navigationTitle("Shopping")
            .navigationSubtitle(households.current?.name ?? "")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let code = households.currentCode, let name = households.current?.name {
                        ShareLink(item: inviteMessage(code: code, household: name)) {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                addButton
            }
            .overlay(alignment: .bottom) {
                undoToast
            }
            .sheet(isPresented: $showAdd) {
                ItemFormSheet(mode: .add).id("add")
            }
            .sheet(item: $editing) { item in
                ItemFormSheet(mode: .edit(item)).id("edit-\(item.id)")
            }
            .alert("Something went wrong", isPresented: Binding(get: { list.error != nil }, set: { if !$0 { list.error = nil } })) {
                Button("OK") { list.error = nil }
            } message: {
                Text(list.error ?? "")
            }
            .sensoryFeedback(.impact(weight: .light), trigger: toggleTick)
            .sensoryFeedback(.warning, trigger: deleteTick)
            .sensoryFeedback(.success, trigger: checkoutTick)
        }
    }

    // MARK: content

    @ViewBuilder
    private func content(for household: Household) -> some View {
        let sections = list.sections
        if list.loading && list.items.isEmpty {
            ProgressView()
        } else if sections.isEmpty {
            ScrollView {
                EmptyState(symbol: "cart.fill", title: "Nothing to buy", text: "Tap + when something runs out at home. Everyone in the household sees it instantly.")
                    .padding(.top, 60)
            }
            .refreshable { await list.load(householdID: household.id) }
        } else {
            List {
                ForEach(sections.needed) { section in
                    Section {
                        ForEach(section.items) { item in
                            row(item)
                        }
                    } header: {
                        ShopSectionHeader(section: section) {
                            checkoutTick += 1
                            Task { await list.checkout(shopID: .some(section.shopID)) }
                        }
                    } footer: {
                        if section.shopID == nil {
                            Text("Long-press an item to assign a shop.")
                        }
                    }
                }
                if !sections.bought.isEmpty {
                    Section {
                        if showBought {
                            ForEach(sections.bought) { item in
                                row(item)
                            }
                        }
                    } header: {
                        HStack {
                            Button {
                                withAnimation(.snappy) { showBought.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Recently bought (\(sections.bought.count))")
                                    Image(systemName: showBought ? "chevron.down" : "chevron.right")
                                }
                            }
                            .accessibilityIdentifier(A11y.listBoughtToggle)
                            Spacer()
                            Menu {
                                Button("Clear recently bought", systemImage: "trash", role: .destructive) {
                                    Task { await list.clearBought() }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityIdentifier(A11y.listBoughtMenu)
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .contentMargins(.bottom, 88, for: .scrollContent)   // room to scroll past the floating +
            .scrollContentBackground(.hidden)
            .background { Color(.systemGroupedBackground).ignoresSafeArea() }
            .background { HeroGlow() }
            .scrollDismissesKeyboard(.interactively)
            .animation(.snappy, value: sections)
            .refreshable { await list.load(householdID: household.id) }
        }
    }

    private func row(_ item: ShoppingListItem) -> some View {
        Button {
            toggleTick += 1
            Task { await list.toggle(item) }
        } label: {
            ItemRow(item: item)
        }
        // Default button style on purpose: inside a List cell, .plain buttons and tap gestures
        // never receive synthetic touches (AXe/XCUITest), the cell-selection path does.
        // .tint(.primary) keeps the label from taking the accent colour.
        .tint(.primary)
        .accessibilityIdentifier(A11y.listItem(item.name))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleTick += 1
                    Task { item.status == .bought ? await list.toggle(item) : await list.markBought(item) }
                } label: {
                    Label(item.status == .bought ? "Un-buy" : "Bought", systemImage: item.status == .bought ? "arrow.uturn.backward" : "cart.fill")
                }
                .tint(.green)
                .accessibilityIdentifier(A11y.listItemBought(item.name))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteTick += 1
                    list.delete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier(A11y.listItemDelete(item.name))
            }
            .contextMenu {
                Menu("Move to shop", systemImage: "storefront") {
                    ForEach(list.shops) { shop in
                        Button(shop.name) { Task { await list.move(item, toShop: shop.id) } }
                            .disabled(shop.id == item.shopId)
                    }
                    Divider()
                    Button("Unsorted") { Task { await list.move(item, toShop: nil) } }
                        .disabled(item.shopId == nil)
                }
                Button("Edit", systemImage: "pencil") { editing = item }
                Button(item.status == .bought ? "Mark needed" : "Mark bought", systemImage: "checkmark.circle") {
                    Task { item.status == .bought ? await list.toggle(item) : await list.markBought(item) }
                }
                if item.status != .bought {
                    Button(item.status == .inBasket ? "Take out of basket" : "In the basket", systemImage: "basket") {
                        Task { await list.toggle(item) }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleteTick += 1
                    list.delete(item)
                }
            }
            .accessibilityActions {
                Button(item.status == .needed ? "Mark bought" : "Mark needed") { Task { await list.toggle(item) } }
                Button("Edit") { editing = item }
                Button("Delete") { list.delete(item) }
            }
    }

    // MARK: add button

    /// The one call to action: a floating + above the tab bar, always one tap away.
    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("Add to the list")
        .accessibilityIdentifier(A11y.listAdd)
    }

    // MARK: undo

    @ViewBuilder
    private var undoToast: some View {
        if let pending = list.lastPendingDelete {
            HStack {
                Text("Deleted \(pending.item.name)")
                    .lineLimit(1)
                    .accessibilityIdentifier(A11y.listUndoToast)
                Spacer()
                Button("Undo") { list.undoDelete(pending.id) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(A11y.listUndo)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(.secondary.opacity(0.2)))
            .padding(.horizontal)
            .padding(.bottom, 64)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

func inviteMessage(code: String, household: String) -> String {
    "Join our household \"\(household)\" in Household Helper. Invite code: \(code)"
}

struct ItemRow: View {
    @Environment(ListStore.self) private var list
    @Environment(AuthStore.self) private var auth
    let item: ShoppingListItem

    var body: some View {
        HStack(spacing: 12) {
            CheckMark(status: item.status, tint: list.shop(item.shopId).map { Brand.shopColor($0.name) } ?? Brand.unsortedColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.status == .bought)
                    .foregroundStyle(item.status == .bought ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let q = item.quantity, !q.isEmpty { Chip(text: q, tint: list.shop(item.shopId).map { Brand.shopColor($0.name) } ?? Brand.primary) }
                    if let by = item.addedBy, by != auth.uid, let name = Self.actorName(by) {
                        Text("added by \(name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Display names arrive with push/member events later; dev uids are readable as-is.
    private static func actorName(_ uid: String) -> String? {
        uid.hasPrefix("dev-") ? String(uid.dropFirst(4)).capitalized : nil
    }

    private var accessibilityText: String {
        var parts = [item.name]
        if let q = item.quantity, !q.isEmpty { parts.append(q) }
        parts.append(item.status == .bought ? "bought" : item.status == .inBasket ? "in basket" : "needed")
        if let shop = list.shop(item.shopId) { parts.append(shop.name) }
        return parts.joined(separator: ", ")
    }
}

/// Add (floating +) and edit (context menu › Edit): product with typing hints from the household's
/// products, size/quantity, and a shop picker that can create a shop on the spot.
struct ItemFormSheet: View {
    enum Mode { case add, edit(ShoppingListItem) }

    @Environment(ListStore.self) private var list
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var name = ""
    @State private var quantity = ""
    @State private var shopSelection = ""      // "" = not sure yet, shop id, or newShopTag
    @State private var newShopName = ""
    @State private var pickedProduct: CatalogItem?
    @FocusState private var nameFocused: Bool
    private let newShopTag = "__new__"

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suggestions: [CatalogItem] {
        list.suggestions(for: name).filter { $0.name.caseInsensitiveCompare(trimmedName) != .orderedSame }
    }
    private var canSubmit: Bool {
        !trimmedName.isEmpty && (shopSelection != newShopTag || !newShopName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("What ran out?", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if canSubmit { submit() } }
                        .onChange(of: name) { _, new in
                            // A hint stays linked only while the name is still the hint's name.
                            if let p = pickedProduct, p.name.caseInsensitiveCompare(new.trimmingCharacters(in: .whitespaces)) != .orderedSame {
                                pickedProduct = nil
                            }
                        }
                        .accessibilityIdentifier(A11y.listInput)
                    ForEach(suggestions) { product in
                        Button {
                            pick(product)
                        } label: {
                            HStack {
                                Label(product.name, systemImage: "clock.arrow.circlepath")
                                Spacer()
                                if let unit = product.defaultUnit, !unit.isEmpty {
                                    Text(unit).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier(A11y.listSuggestion(product.name))
                    }
                }
                Section("Size / quantity") {
                    TextField("e.g. 2, 1 gal, large pack", text: $quantity)
                        .submitLabel(.done)
                        .onSubmit { if canSubmit { submit() } }
                        .accessibilityIdentifier(A11y.listQuantity)
                }
                Section("Shop") {
                    Picker("Shop", selection: $shopSelection) {
                        Text("Not sure yet").tag("")
                        ForEach(list.shops) { shop in
                            Text(shop.name).tag(shop.id)
                        }
                        Label("New shop…", systemImage: "plus").tag(newShopTag)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(A11y.listShop)
                    if shopSelection == newShopTag {
                        TextField("Shop name", text: $newShopName)
                            .submitLabel(.done)
                            .onSubmit { if canSubmit { submit() } }
                            .accessibilityIdentifier(A11y.listNewShop)
                    }
                }
            }
            .navigationTitle(isEdit ? "Edit item" : "Add to the list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Save" : "Add") { submit() }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier(A11y.listSubmit)
                }
            }
            .onAppear {
                // Always start clean: nothing from a previous presentation may leak into this one.
                pickedProduct = nil
                newShopName = ""
                if case let .edit(item) = mode {
                    name = item.name
                    quantity = item.quantity ?? ""
                    shopSelection = item.shopId ?? ""
                } else {
                    name = ""
                    quantity = ""
                    shopSelection = ""
                    nameFocused = true
                }
            }
        }
        .presentationDetents([.large])
    }

    /// A hint fills in what the user left empty; the product stays linked unless the name changes.
    private func pick(_ product: CatalogItem) {
        name = product.name
        pickedProduct = product
        if quantity.isEmpty, let unit = product.defaultUnit { quantity = unit }
        if shopSelection.isEmpty, let shop = product.shopId, list.shop(shop) != nil { shopSelection = shop }
    }

    private func submit() {
        let itemName = trimmedName
        let qty = quantity.trimmingCharacters(in: .whitespaces)
        let shopName = newShopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = shopSelection
        let product: CatalogItem? = {
            guard let p = pickedProduct, p.name.caseInsensitiveCompare(itemName) == .orderedSame else { return nil }
            return p
        }()
        let editing: ShoppingListItem? = { if case let .edit(item) = mode { return item } else { return nil } }()
        dismiss()
        Task {
            var shopID: String? = selection.isEmpty ? nil : selection
            if selection == newShopTag {
                shopID = await list.addShop(name: shopName)?.id
            }
            if let item = editing {
                await list.edit(item, name: itemName, quantity: qty.isEmpty ? nil : qty)
                if item.shopId != shopID, let current = list.items.first(where: { $0.id == item.id }) {
                    await list.move(current, toShop: shopID)
                }
            } else {
                await list.add(name: itemName, shopID: shopID, catalogItemID: product?.id, quantity: qty.isEmpty ? nil : qty)
            }
        }
    }
}

/// Section header: shop identity, progress, and the Checkout call to action once something is ticked.
struct ShopSectionHeader: View {
    let section: ListGrouping.Section
    let checkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ShopGlyph(name: section.shopID == nil ? nil : section.title, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(Color(.label))   // List headers default to secondary
                    Text(section.basketCount > 0 ? "\(section.basketCount) of \(section.items.count) in the basket" : "\(section.items.count) to buy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if section.basketCount > 0 {
                    Button(action: checkout) {
                        // Not a Label: List section headers render labels title-only.
                        HStack(spacing: 6) {
                            Image(systemName: "cart.fill")
                            Text("Checkout \(section.basketCount)")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Brand.basket)
                    .accessibilityIdentifier(A11y.listCheckout(section.title))
                }
            }
            if section.basketCount > 0 {
                ProgressCapsule(value: Double(section.basketCount) / Double(max(1, section.items.count)), tint: Brand.basket)
                    .padding(.leading, 40)
            }
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

/// The tick: hollow ring in the shop's colour, filled green with a bounce when in the basket,
/// muted when bought.
struct CheckMark: View {
    let status: ItemStatus
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(status == .needed ? tint.opacity(0.55) : .clear, lineWidth: 2)
                .frame(width: 26, height: 26)
            if status != .needed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, status == .inBasket ? Brand.basket : Color.secondary.opacity(0.6))
                    .symbolEffect(.bounce, value: status)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .animation(.snappy, value: status)
    }
}

/// Friendly empty state with a gradient symbol.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Brand.primary.opacity(0.35), radius: 16, y: 8)
            Text(title).font(.title2.bold())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}
