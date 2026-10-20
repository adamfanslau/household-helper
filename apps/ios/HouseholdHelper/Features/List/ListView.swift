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
        }
    }

    // MARK: content

    @ViewBuilder
    private func content(for household: Household) -> some View {
        let sections = list.sections
        if list.loading && list.items.isEmpty {
            ProgressView()
        } else if sections.isEmpty {
            ContentUnavailableView {
                Label("Nothing to buy", systemImage: "cart")
            } description: {
                Text("Add items as they run out at home.")
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
                        Text("\(section.title) · \(section.items.count)")
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
                    Task { await list.toggle(item) }
                } label: {
                    Label(item.status == .needed ? "Bought" : "Un-buy", systemImage: item.status == .needed ? "cart.badge.checkmark" : "arrow.uturn.backward")
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
                Button(item.status == .needed ? "Mark bought" : "Mark needed", systemImage: "checkmark.circle") {
                    Task { await list.toggle(item) }
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
            Image(systemName: item.status == .bought ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status == .bought ? Color.accentColor : .secondary)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.status == .bought)
                    .foregroundStyle(item.status == .bought ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let q = item.quantity, !q.isEmpty { parts.append(q) }
        if let by = item.addedBy, by != auth.uid, let name = Self.actorName(by) { parts.append("added by \(name)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Display names arrive with push/member events later; dev uids are readable as-is.
    private static func actorName(_ uid: String) -> String? {
        uid.hasPrefix("dev-") ? String(uid.dropFirst(4)).capitalized : nil
    }

    private var accessibilityText: String {
        var parts = [item.name]
        if let q = item.quantity, !q.isEmpty { parts.append(q) }
        parts.append(item.status == .bought ? "bought" : "needed")
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
