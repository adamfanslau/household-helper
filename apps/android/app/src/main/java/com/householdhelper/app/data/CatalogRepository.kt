package com.householdhelper.app.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Catalog of one shop (shop detail screen). */
class CatalogRepository(private val api: ApiClient, val householdId: String, val shopId: String) {
    private val _items = MutableStateFlow<List<CatalogItem>>(emptyList())
    val items: StateFlow<List<CatalogItem>> = _items
    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded
    val error = MutableStateFlow<String?>(null)
    private val scope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    data class PendingDelete(val item: CatalogItem, val job: Job)
    private val _pendingDeletes = MutableStateFlow<List<PendingDelete>>(emptyList())
    val pendingDeletes: StateFlow<List<PendingDelete>> = _pendingDeletes
    private val base = "/v1/households/$householdId/shops/$shopId/catalog-items"

    suspend fun load() {
        try {
            val hidden = _pendingDeletes.value.map { it.item.id }.toSet()
            _items.value = api.get<List<CatalogItem>>(base).filter { it.id !in hidden }
            error.value = null
        } catch (e: Exception) { error.value = e.message } finally { _loaded.value = true }
    }

    suspend fun add(name: String, defaultUnit: String? = null) {
        val trimmed = name.trim(); if (trimmed.isEmpty()) return
        try {
            val body = buildMap { put("name", trimmed); defaultUnit?.trim()?.takeIf { it.isNotEmpty() }?.let { put("default_unit", it) } }
            val saved: CatalogItem = api.post(base, body)
            _items.update { (it + saved).sortedBy { c -> c.name.lowercase() } }
        } catch (e: Exception) { error.value = e.message }
    }

    /** Removes now, deletes on the server after [graceMs] unless [undoDelete] is called. */
    fun delete(item: CatalogItem, graceMs: Long = 5_000) {
        _items.update { list -> list.filter { it.id != item.id } }
        val job = scope.launch {
            delay(graceMs)
            _pendingDeletes.update { p -> p.filter { it.item.id != item.id } }
            try { api.delete("$base/${item.id}") } catch (e: Exception) { error.value = e.message; load() }
        }
        _pendingDeletes.update { it + PendingDelete(item, job) }
    }

    fun undoDelete(id: String) {
        val p = _pendingDeletes.value.firstOrNull { it.item.id == id } ?: return
        p.job.cancel()
        _pendingDeletes.update { list -> list.filter { it.item.id != id } }
        if (_items.value.none { it.id == id }) _items.update { (it + p.item).sortedBy { c -> c.name.lowercase() } }
    }

    fun apply(change: ChangeEvent) {
        if (change.table != "catalog_items") return
        if (change.type == "delete") {
            val id = (change.row as? kotlinx.serialization.json.JsonObject)?.get("id")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content } ?: return
            _items.update { list -> list.filter { it.id != id } }
            return
        }
        val row = runCatching { HHJson.decodeFromJsonElement(CatalogItem.serializer(), change.row) }.getOrNull() ?: return
        if (row.shopId != shopId) return
        _items.update { list -> (if (list.any { it.id == row.id }) list.map { if (it.id == row.id) row else it } else list + row).sortedBy { it.name.lowercase() } }
    }
}
