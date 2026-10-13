import SwiftUI

/// A shop's catalog: "To list" adds a list item (server fills shop and default unit).
struct ShopDetailView: View {
    @Environment(HouseholdStore.self) private var households
    @Environment(ListStore.self) private var list
    @Environment(EventsClient.self) private var events
    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    let shopID: String
    @State private var catalog: CatalogStore?
    @State private var draft = ""
    @State private var added: Set<String> = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var addedTick = 0

    private var shop: Shop? { list.shop(shopID) }

    var body: some View {
        Group {
            if let catalog {
                content(catalog)
            } else {
                ProgressView()
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
        .task(id: shopID) {
            guard let hid = households.current?.id else { return }
            let store = CatalogStore(api: api, householdID: hid, shopID: shopID)
            catalog = store
            await store.load()
        }
        .onChange(of: events.state) { _, state in
            if state == .connected { Task { await catalog?.load() } }
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
            Text("Its catalog is removed. Items on the list move to Unsorted.")
        }
        .sensoryFeedback(.success, trigger: addedTick)
    }

    @ViewBuilder
    private func content(_ catalog: CatalogStore) -> some View {
        Group {
            if catalog.loaded && catalog.items.isEmpty {
                ContentUnavailableView {
                    Label("No items for this shop yet", systemImage: "basket")
                } description: {
                    Text("Add the things you usually buy here.")
                }
            } else {
                List {
                    ForEach(catalog.items) { item in
                        // The whole row is the action (default button style: cell-selection path, see ListView).
                        Button {
                            toList(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).foregroundStyle(.primary)
                                    if let unit = item.defaultUnit, !unit.isEmpty {
                                        Text(unit).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier(A11y.shopRow(item.name))
                                Spacer()
                                Label(added.contains(item.id) ? "Added" : "To list",
                                      systemImage: added.contains(item.id) ? "checkmark" : "plus")
                                    .contentTransition(.symbolEffect(.replace))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background((added.contains(item.id) ? Color.green : Color.accentColor).opacity(0.15), in: Capsule())
                                    .foregroundStyle(added.contains(item.id) ? Color.green : Color.accentColor)
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier(A11y.shopToList(item.name))
                        .accessibilityLabel("\(item.name), add to list")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await catalog.delete(item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier(A11y.shopRowDelete(item.name))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await catalog.load() }
            }
        }
        .safeAreaBar(edge: .bottom) {
            HStack(spacing: 10) {
                TextField("Add an item this shop sells", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { add(catalog) }
                    .accessibilityIdentifier(A11y.shopInput)
                Button { add(catalog) } label: {
                    Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 24, height: 24)
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add catalog item")
                .accessibilityIdentifier(A11y.shopAdd)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func toList(_ item: CatalogItem) {
        guard !added.contains(item.id) else { return }
        added.insert(item.id)
        addedTick += 1
        Task {
            await list.add(name: item.name, shopID: shopID, catalogItemID: item.id, quantity: nil)
            try? await Task.sleep(for: .seconds(1.5))
            added.remove(item.id)
        }
    }

    private func add(_ catalog: CatalogStore) {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        draft = ""
        Task { await catalog.add(name: name) }
    }
}
