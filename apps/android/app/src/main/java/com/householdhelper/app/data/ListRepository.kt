package com.householdhelper.app.data

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID

/**
 * Items and shops of the selected household: optimistic mutations, delayed deletes with undo,
 * and SSE change application (insert de-dupes by id, update replaces, delete removes).
 */
class ListRepository(private val api: ApiClient) {
    private val _items = MutableStateFlow<List<ShoppingListItem>>(emptyList())
    val items: StateFlow<List<ShoppingListItem>> = _items
    private val _shops = MutableStateFlow<List<Shop>>(emptyList())
    val shops: StateFlow<List<Shop>> = _shops
    /** The household's products (typing hints), kept in step over SSE. */
    private val _products = MutableStateFlow<List<CatalogItem>>(emptyList())
    val products: StateFlow<List<CatalogItem>> = _products
    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading
    val error = MutableStateFlow<String?>(null)
    var loadedHouseholdId: String? = null
        private set
    private val hid: String? get() = loadedHouseholdId
    // Lazy: Dispatchers.Main does not exist in plain unit tests (ListRepository.applied).
    private val scope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    data class PendingDelete(val item: ShoppingListItem, val job: Job)
    private val _pendingDeletes = MutableStateFlow<List<PendingDelete>>(emptyList())
    val pendingDeletes: StateFlow<List<PendingDelete>> = _pendingDeletes

    @Serializable
    data class NewItemBody(val id: String, val name: String, val shopId: String? = null, val catalogItemId: String? = null, val quantity: String? = null)

    suspend fun load(householdId: String) {
        _loading.value = loadedHouseholdId != householdId
        try {
            coroutineScope {
                val i = async { api.get<List<ShoppingListItem>>("/v1/households/$householdId/items") }
                val s = async { api.get<List<Shop>>("/v1/households/$householdId/shops") }
                val p = async { api.get<List<CatalogItem>>("/v1/households/$householdId/catalog-items") }
                val hidden = _pendingDeletes.value.map { it.item.id }.toSet()
                _items.value = i.await().filter { it.id !in hidden }
                _shops.value = s.await()
                _products.value = p.await()
            }
            loadedHouseholdId = householdId
            error.value = null
            Log.i(AuthRepository.TAG, "list loaded: ${_items.value.size} items, ${_shops.value.size} shops")
        } catch (e: Exception) {
            error.value = e.message
            Log.e(AuthRepository.TAG, "list load failed: ${e.message}")
        } finally {
            _loading.value = false
        }
    }

    suspend fun refresh() { hid?.let { load(it) } }

    fun clear() {
        _pendingDeletes.value.forEach { it.job.cancel() }
        _pendingDeletes.value = emptyList()
        _items.value = emptyList()
        _shops.value = emptyList()
        _products.value = emptyList()
        loadedHouseholdId = null
    }

    /** Products matching what the user typed: prefix matches first, then anywhere in the name. */
    fun suggestions(query: String, limit: Int = 6): List<CatalogItem> {
        val q = query.trim().lowercase(); if (q.isEmpty()) return emptyList()
        val all = _products.value
        val prefix = all.filter { it.name.lowercase().startsWith(q) }
        val inside = all.filter { !it.name.lowercase().startsWith(q) && it.name.lowercase().contains(q) }
        return (prefix + inside).take(limit)
    }

    fun shop(id: String?): Shop? = id?.let { s -> _shops.value.firstOrNull { it.id == s } }

    // MARK: items

    /** Adds optimistically with a client id so the server echo (and a retry) de-duplicate. */
    suspend fun add(name: String, shopId: String? = null, catalogItemId: String? = null, quantity: String? = null) {
        val h = hid ?: return
        val trimmed = name.trim(); if (trimmed.isEmpty()) return
        val id = UUID.randomUUID().toString()
        val now = Now.iso()
        replace(ShoppingListItem(id, h, trimmed, shopId, catalogItemId, quantity, "needed", null, now, now, null))
        try {
            val saved: ShoppingListItem = api.post("/v1/households/$h/items", NewItemBody(id, trimmed, shopId, catalogItemId, quantity))
            replace(saved)
            bumpNeeded(saved.shopId, 1)
        } catch (e: Exception) {
            _items.update { list -> list.filter { it.id != id } }
            error.value = e.message
        }
    }

    private suspend fun patch(item: ShoppingListItem, body: JsonObject, optimistic: ShoppingListItem) {
        val h = hid ?: return
        replace(optimistic)
        try {
            val saved: ShoppingListItem = api.patch("/v1/households/$h/items/${item.id}", body)
            replace(saved)
        } catch (e: Exception) {
            replace(item)
            error.value = e.message
        }
    }

    /** Tap: needed ⇄ in the basket; a bought item goes back to needed (un-buy). */
    suspend fun toggle(item: ShoppingListItem) {
        val next = item.copy(status = if (item.status == "needed") "in_basket" else "needed", boughtAt = null)
        if (item.isBought) bumpNeeded(item.shopId, 1)
        patch(item, JsonObject(mapOf("status" to JsonPrimitive(next.status))), next)
    }

    /** Swipe / sheet: straight to bought (skipping the basket). */
    suspend fun markBought(item: ShoppingListItem) {
        if (item.isBought) return
        bumpNeeded(item.shopId, -1)
        patch(item, JsonObject(mapOf("status" to JsonPrimitive("bought"))), item.copy(status = "bought", boughtAt = Now.iso()))
    }

    /** Checkout: the basket of one shop (shopId), of Unsorted (shopId = null, unsorted = true) or everything. */
    suspend fun checkout(shopId: String?, unsorted: Boolean = false) {
        val h = hid ?: return
        val before = _items.value
        val inScope: (ShoppingListItem) -> Boolean = { it.isInBasket && (shopId == null && !unsorted || it.shopId == shopId) }
        val now = Now.iso()
        _items.update { list -> list.map { if (inScope(it)) it.copy(status = "bought", boughtAt = now) else it } }
        before.filter(inScope).forEach { bumpNeeded(it.shopId, -1) }
        val body = if (shopId != null) JsonObject(mapOf("shop_id" to JsonPrimitive(shopId))) else if (unsorted) JsonObject(mapOf("shop_id" to JsonNull)) else JsonObject(emptyMap())
        try {
            val saved: List<ShoppingListItem> = api.post("/v1/households/$h/items/checkout", body)
            saved.forEach { replace(it) }
        } catch (e: Exception) { _items.value = before; error.value = e.message }
    }

    suspend fun move(item: ShoppingListItem, shopId: String?) {
        if (item.shopId == shopId) return
        if (!item.isBought) { bumpNeeded(item.shopId, -1); bumpNeeded(shopId, 1) }
        patch(item, JsonObject(mapOf("shop_id" to (shopId?.let { JsonPrimitive(it) } ?: JsonNull))), item.copy(shopId = shopId))
    }

    suspend fun edit(item: ShoppingListItem, name: String, quantity: String?) {
        val trimmed = name.trim(); if (trimmed.isEmpty()) return
        val q = quantity?.trim()?.takeIf { it.isNotEmpty() }
        patch(item, JsonObject(mapOf("name" to JsonPrimitive(trimmed), "quantity" to (q?.let { JsonPrimitive(it) } ?: JsonNull))), item.copy(name = trimmed, quantity = q))
    }

    /** Removes now, deletes on the server after [graceMs] unless [undoDelete] is called. */
    fun delete(item: ShoppingListItem, graceMs: Long = 5_000) {
        val h = hid ?: return
        _items.update { list -> list.filter { it.id != item.id } }
        if (!item.isBought) bumpNeeded(item.shopId, -1)
        val job = scope.launch {
            delay(graceMs)
            _pendingDeletes.update { p -> p.filter { it.item.id != item.id } }
            try { api.delete("/v1/households/$h/items/${item.id}") } catch (e: Exception) { error.value = e.message; refresh() }
        }
        _pendingDeletes.update { it + PendingDelete(item, job) }
    }

    fun undoDelete(id: String) {
        val p = _pendingDeletes.value.firstOrNull { it.item.id == id } ?: return
        p.job.cancel()
        _pendingDeletes.update { list -> list.filter { it.item.id != id } }
        if (_items.value.none { it.id == id }) {
            replace(p.item)
            if (!p.item.isBought) bumpNeeded(p.item.shopId, 1)
        }
    }

    suspend fun clearBought() {
        val h = hid ?: return
        val before = _items.value
        _items.update { list -> list.filter { !it.isBought } }
        try { api.delete("/v1/households/$h/items?status=bought") } catch (e: Exception) { _items.value = before; error.value = e.message }
    }

    // MARK: shops

    suspend fun addShop(name: String): Shop? {
        val h = hid ?: return null
        val trimmed = name.trim(); if (trimmed.isEmpty()) return null
        _shops.value.firstOrNull { it.name.equals(trimmed, ignoreCase = true) }?.let { return it }
        return try {
            val shop: Shop = api.post("/v1/households/$h/shops", mapOf("name" to trimmed))
            replaceShop(shop)
            shop
        } catch (e: Exception) { error.value = e.message; null }
    }

    suspend fun renameShop(shop: Shop, name: String) {
        val h = hid ?: return
        val trimmed = name.trim(); if (trimmed.isEmpty() || trimmed == shop.name) return
        try {
            val saved: Shop = api.patch("/v1/households/$h/shops/${shop.id}", mapOf("name" to trimmed))
            replaceShop(saved)
        } catch (e: Exception) { error.value = e.message }
    }

    /** The server sets shop_id NULL on the shop's items (they become Unsorted). */
    suspend fun deleteShop(shop: Shop) {
        val h = hid ?: return
        val beforeShops = _shops.value; val beforeItems = _items.value
        _shops.update { list -> list.filter { it.id != shop.id } }
        _items.update { list -> list.map { if (it.shopId == shop.id) it.copy(shopId = null) else it } }
        try { api.delete("/v1/households/$h/shops/${shop.id}") } catch (e: Exception) { _shops.value = beforeShops; _items.value = beforeItems; error.value = e.message }
    }

    // MARK: realtime

    /** Applies one change frame; returns true when a refetch is needed (shop deletions move items). */
    fun apply(change: ChangeEvent): Boolean {
        when (change.table to change.type) {
            "shopping_list_items" to "delete" -> {
                val id = change.row.jsonObject["id"]?.jsonPrimitive?.content ?: return false
                _pendingDeletes.update { p -> p.filter { it.item.id != id } }
                _items.update { list -> list.filter { it.id != id } }
            }
            "shopping_list_items" to "insert", "shopping_list_items" to "update" -> {
                val row = runCatching { HHJson.decodeFromJsonElement(ShoppingListItem.serializer(), change.row) }.getOrNull() ?: return false
                if (_pendingDeletes.value.any { it.item.id == row.id }) return false
                replace(row)
            }
            "shops" to "delete" -> {
                val id = change.row.jsonObject["id"]?.jsonPrimitive?.content ?: return false
                _shops.update { list -> list.filter { it.id != id } }
                _items.update { list -> list.map { if (it.shopId == id) it.copy(shopId = null) else it } }
                return true
            }
            "shops" to "insert", "shops" to "update" -> {
                runCatching { HHJson.decodeFromJsonElement(Shop.serializer(), change.row) }.getOrNull()?.let { replaceShop(it) }
            }
            "catalog_items" to "delete" -> {
                val id = change.row.jsonObject["id"]?.jsonPrimitive?.content ?: return false
                _products.update { list -> list.filter { it.id != id } }
            }
            "catalog_items" to "insert", "catalog_items" to "update" -> {
                val row = runCatching { HHJson.decodeFromJsonElement(CatalogItem.serializer(), change.row) }.getOrNull() ?: return false
                _products.update { list -> (if (list.any { it.id == row.id }) list.map { if (it.id == row.id) row else it } else list + row).sortedBy { it.name.lowercase() } }
            }
        }
        return false
    }

    // MARK: helpers

    private fun replace(item: ShoppingListItem) {
        _items.update { list ->
            if (list.any { it.id == item.id }) list.map { if (it.id == item.id) item else it }
            else (list + item).sortedWith(compareBy({ it.createdAt }, { it.id }))
        }
    }

    private fun replaceShop(shop: Shop) {
        _shops.update { list ->
            (if (list.any { it.id == shop.id }) list.map { if (it.id == shop.id) shop else it } else list + shop)
                .sortedWith(compareBy({ it.sortOrder }, { it.createdAt }))
        }
    }

    private fun bumpNeeded(shopId: String?, delta: Int) {
        shopId ?: return
        _shops.update { list -> list.map { if (it.id == shopId) it.copy(neededCount = maxOf(0, it.neededCount + delta)) else it } }
    }

    companion object {
        /** Pure helper for tests: items after applying one change. */
        fun applied(items: List<ShoppingListItem>, change: ChangeEvent): List<ShoppingListItem> {
            val repo = ListRepository(ApiClient(AuthRepository.NONE, "http://localhost"))
            repo._items.value = items
            repo.loadedHouseholdId = "test"
            repo.apply(change)
            return repo._items.value
        }
    }
}

object Now {
    fun iso(): String = java.time.format.DateTimeFormatter.ISO_INSTANT.format(java.time.Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS))
}

/** Pure grouping: needed items by shop in sort order, Unsorted last, bought separate. */
object ListGrouping {
    const val UNSORTED = "__unsorted__"
    data class Section(val id: String, val title: String, val shopId: String?, val items: List<ShoppingListItem>) {
        val basketCount: Int get() = items.count { it.isInBasket }
    }
    data class Sections(val needed: List<Section>, val bought: List<ShoppingListItem>) {
        val isEmpty: Boolean get() = needed.isEmpty() && bought.isEmpty()
    }

    fun sections(items: List<ShoppingListItem>, shops: List<Shop>): Sections {
        val byShop = LinkedHashMap<String, MutableList<ShoppingListItem>>()
        val bought = ArrayList<ShoppingListItem>()
        for (item in items) {
            if (item.isBought) bought += item else byShop.getOrPut(item.shopId ?: UNSORTED) { ArrayList() } += item
        }
        // Ticked items sink to the bottom of their shop so what is still to find stays on top.
        for (key in byShop.keys.toList()) byShop[key] = byShop[key]!!.let { l -> (l.filter { !it.isInBasket } + l.filter { it.isInBasket }).toMutableList() }
        val needed = ArrayList<Section>()
        for (shop in shops.sortedWith(compareBy({ it.sortOrder }, { it.createdAt }))) {
            byShop[shop.id]?.takeIf { it.isNotEmpty() }?.let { needed += Section(shop.id, shop.name, shop.id, it) }
        }
        byShop[UNSORTED]?.takeIf { it.isNotEmpty() }?.let { needed += Section(UNSORTED, "Unsorted", null, it) }
        return Sections(needed, bought)
    }
}
