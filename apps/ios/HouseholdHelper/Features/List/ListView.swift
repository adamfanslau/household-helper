import SwiftUI

/// Read-only in step I1: sections per shop in sort order, Unsorted last, collapsible bought.
struct ListView: View {
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @State private var showBought = false

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
        }
    }

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
                            ItemRow(item: item)
                        }
                    } header: {
                        Text("\(section.title) · \(section.items.count)")
                    }
                }
                if !sections.bought.isEmpty {
                    Section {
                        if showBought {
                            ForEach(sections.bought) { item in
                                ItemRow(item: item)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation(.snappy) { showBought.toggle() }
                        } label: {
                            HStack {
                                Text("Recently bought (\(sections.bought.count))")
                                Spacer()
                                Image(systemName: showBought ? "chevron.down" : "chevron.right")
                            }
                        }
                        .accessibilityIdentifier(A11y.listBoughtToggle)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await list.load(householdID: household.id) }
        }
    }
}

struct ItemRow: View {
    let item: ShoppingListItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.status == .bought ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status == .bought ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .strikethrough(item.status == .bought)
                    .foregroundStyle(item.status == .bought ? .secondary : .primary)
                if let quantity = item.quantity, !quantity.isEmpty {
                    Text(quantity).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(A11y.listItem(item.name))
    }

    private var accessibilityText: String {
        var parts = [item.name]
        if let q = item.quantity, !q.isEmpty { parts.append(q) }
        parts.append(item.status == .bought ? "bought" : "needed")
        return parts.joined(separator: ", ")
    }
}
