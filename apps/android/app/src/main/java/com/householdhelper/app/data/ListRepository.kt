package com.householdhelper.app.data

import android.util.Log
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Items and shops of the selected household (read side for A1; mutations and realtime in A2). */
class ListRepository(private val api: ApiClient) {
    private val _items = MutableStateFlow<List<ShoppingListItem>>(emptyList())
    val items: StateFlow<List<ShoppingListItem>> = _items
    private val _shops = MutableStateFlow<List<Shop>>(emptyList())
    val shops: StateFlow<List<Shop>> = _shops
    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading
    val error = MutableStateFlow<String?>(null)
    var loadedHouseholdId: String? = null
        private set

    suspend fun load(householdId: String) {
        _loading.value = loadedHouseholdId != householdId
        try {
            coroutineScope {
                val i = async { api.get<List<ShoppingListItem>>("/v1/households/$householdId/items") }
                val s = async { api.get<List<Shop>>("/v1/households/$householdId/shops") }
                _items.value = i.await()
                _shops.value = s.await()
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

    fun clear() {
        _items.value = emptyList()
        _shops.value = emptyList()
        loadedHouseholdId = null
    }
}

/** Pure grouping: needed items by shop in sort order, Unsorted last, bought separate. */
object ListGrouping {
    const val UNSORTED = "__unsorted__"
    data class Section(val id: String, val title: String, val shopId: String?, val items: List<ShoppingListItem>)
    data class Sections(val needed: List<Section>, val bought: List<ShoppingListItem>) {
        val isEmpty: Boolean get() = needed.isEmpty() && bought.isEmpty()
    }

    fun sections(items: List<ShoppingListItem>, shops: List<Shop>): Sections {
        val byShop = LinkedHashMap<String, MutableList<ShoppingListItem>>()
        val bought = ArrayList<ShoppingListItem>()
        for (item in items) {
            if (item.isBought) bought += item else byShop.getOrPut(item.shopId ?: UNSORTED) { ArrayList() } += item
        }
        val needed = ArrayList<Section>()
        for (shop in shops.sortedWith(compareBy({ it.sortOrder }, { it.createdAt }))) {
            byShop[shop.id]?.takeIf { it.isNotEmpty() }?.let { needed += Section(shop.id, shop.name, shop.id, it) }
        }
        byShop[UNSORTED]?.takeIf { it.isNotEmpty() }?.let { needed += Section(UNSORTED, "Unsorted", null, it) }
        return Sections(needed, bought)
    }
}
