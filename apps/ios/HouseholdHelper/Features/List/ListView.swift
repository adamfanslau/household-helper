import SwiftUI

/// The home screen: needed items grouped by shop, Unsorted last, "Recently bought" collapsible,
/// add bar pinned above the keyboard, swipe + context-menu actions, undo on delete.
struct ListView: View {
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @State private var showBought = false
    @State private var draft = ""
    @FocusState private var addFocused: Bool
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
            .safeAreaBar(edge: .bottom) {
                addBar
            }
            .overlay(alignment: .bottom) {
                undoToast
            }
            .sheet(item: $editing) { item in
                EditItemSheet(item: item)
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

    // MARK: add bar

    private var addBar: some View {
        HStack(spacing: 10) {
            TextField("Add something we ran out of…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($addFocused)
                .onSubmit { submit(keepFocus: true) }
                .accessibilityIdentifier(A11y.listInput)
            Button {
                submit(keepFocus: false)
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glassProminent)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add item")
            .accessibilityIdentifier(A11y.listAdd)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func submit(keepFocus: Bool) {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        draft = ""
        addFocused = keepFocus
        Task { await list.add(name: name) }
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

/// Name + quantity editor (context menu › Edit).
struct EditItemSheet: View {
    @Environment(ListStore.self) private var list
    @Environment(\.dismiss) private var dismiss
    let item: ShoppingListItem
    @State private var name = ""
    @State private var quantity = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier(A11y.editName)
                TextField("Quantity (optional)", text: $quantity)
                    .accessibilityIdentifier(A11y.editQuantity)
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await list.edit(item, name: name, quantity: quantity) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier(A11y.editSave)
                }
            }
            .onAppear {
                name = item.name
                quantity = item.quantity ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}
