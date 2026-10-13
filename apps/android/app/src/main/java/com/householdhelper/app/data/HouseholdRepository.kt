package com.householdhelper.app.data

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.prefs: DataStore<Preferences> by preferencesDataStore("hh")

/** The caller's households, the selected one (persisted), invites, create/join (join selects). */
class HouseholdRepository(private val context: Context, private val api: ApiClient) {
    private val _households = MutableStateFlow<List<Household>>(emptyList())
    val households: StateFlow<List<Household>> = _households
    private val _current = MutableStateFlow<Household?>(null)
    val current: StateFlow<Household?> = _current
    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded
    private val _invites = MutableStateFlow<List<Invite>>(emptyList())
    val invites: StateFlow<List<Invite>> = _invites
    val error = MutableStateFlow<String?>(null)

    private val currentKey = stringPreferencesKey("currentHouseholdId")

    suspend fun load() {
        try {
            val list: List<Household> = api.get("/v1/households")
            _households.value = list
            val saved = context.prefs.data.map { it[currentKey] }.first()
            val next = list.firstOrNull { it.id == saved } ?: list.firstOrNull { it.id == _current.value?.id } ?: list.firstOrNull()
            if (next?.id != _current.value?.id) _current.value = next
            if (next != null && next.id != invitesFor) loadInvites()
            error.value = null
            Log.i(AuthRepository.TAG, "households loaded: ${list.size} current=${next?.id ?: "none"}")
        } catch (e: Exception) {
            error.value = e.message
            Log.e(AuthRepository.TAG, "households load failed: ${e.message}")
        } finally {
            _loaded.value = true
        }
    }

    suspend fun select(h: Household) {
        _current.value = h
        context.prefs.edit { it[currentKey] = h.id }
        Log.i(AuthRepository.TAG, "selected household ${h.id}")
        loadInvites()
    }

    suspend fun create(name: String): Household {
        val h: Household = api.post("/v1/households", mapOf("name" to name))
        load()
        select(h)
        return h
    }

    /** Joins and selects the household (the Expo app stayed on the old one). */
    suspend fun join(code: String): Household {
        val h: Household = api.post("/v1/households/join", mapOf("code" to code))
        load()
        select(h)
        return h
    }

    suspend fun rename(name: String) {
        val cur = _current.value ?: return
        val h: Household = api.patch("/v1/households/${cur.id}", mapOf("name" to name))
        apply(h)
    }

    fun apply(h: Household) {
        _households.value = _households.value.map { if (it.id == h.id) it.copy(name = h.name, updatedAt = h.updatedAt) else it }
        if (_current.value?.id == h.id) _current.value = _current.value?.copy(name = h.name, updatedAt = h.updatedAt)
    }

    private var invitesFor: String? = null
    val currentCode: String? get() = _invites.value.firstOrNull { it.revokedAt == null }?.code

    suspend fun loadInvites() {
        val cur = _current.value ?: return
        runCatching { _invites.value = api.get("/v1/households/${cur.id}/invites"); invitesFor = cur.id }
            .onFailure { error.value = it.message }
    }

    suspend fun regenerateInvite() {
        val cur = _current.value ?: return
        try {
            val fresh: Invite = api.post("/v1/households/${cur.id}/invites")
            _invites.value.filter { it.revokedAt == null && it.id != fresh.id }.forEach { old ->
                val _r: Invite = api.post("/v1/households/${cur.id}/invites/${old.id}/revoke")
            }
            loadInvites()
        } catch (e: Exception) {
            error.value = e.message
        }
    }

    fun reset() {
        _households.value = emptyList()
        _current.value = null
        _loaded.value = false
        _invites.value = emptyList()
        invitesFor = null
        error.value = null
    }
}
