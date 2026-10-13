package com.householdhelper.app.data

import android.util.Log
import com.householdhelper.app.BuildConfig
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.sse.SSE
import io.ktor.client.plugins.sse.sse
import io.ktor.client.request.bearerAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * One SSE connection per selected household (Ktor SSE plugin on an OkHttp engine with no read
 * timeout). Reconnects with backoff and a fresh token; `ready` → onReady (refetch), `change` → onChange.
 * Disconnected for more than 3 s surfaces as the "Reconnecting…" pill.
 */
class EventsClient(private val auth: AuthRepository, private val baseUrl: String = BuildConfig.API_BASE_URL) {
    enum class State { IDLE, CONNECTING, CONNECTED, DISCONNECTED }

    private val _state = MutableStateFlow(State.IDLE)
    val state: StateFlow<State> = _state
    private val _disconnectedSince = MutableStateFlow<Long?>(null)
    val disconnectedSince: StateFlow<Long?> = _disconnectedSince
    var onReady: (suspend () -> Unit)? = null
    var onChange: ((ChangeEvent) -> Unit)? = null

    private val client = HttpClient(OkHttp) {
        install(SSE)
        engine { config { readTimeout(0, TimeUnit.MILLISECONDS) } } // the server pings every 25 s
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    var householdId: String? = null
        private set

    fun showsReconnecting(now: Long = System.currentTimeMillis()): Boolean {
        val since = _disconnectedSince.value ?: return false
        return _state.value != State.CONNECTED && now - since > 3_000
    }

    fun connect(householdId: String) {
        if (this.householdId == householdId && job?.isActive == true) return
        disconnect()
        this.householdId = householdId
        _disconnectedSince.value = System.currentTimeMillis()
        Log.i(AuthRepository.TAG, "events connect $householdId")
        job = scope.launch { run(householdId) }
    }

    fun disconnect() {
        job?.cancel(); job = null
        householdId = null
        _state.value = State.IDLE
        _disconnectedSince.value = null
    }

    private suspend fun run(householdId: String) {
        var backoff = 1_000L
        var forceToken = false
        // currentCoroutineContext, not `job`: with an immediate dispatcher the coroutine starts
        // before `job` is assigned.
        while (kotlinx.coroutines.currentCoroutineContext().isActive) {
            _state.value = State.CONNECTING
            try {
                val token = auth.idToken(forceToken); forceToken = false
                withContext(Dispatchers.IO) {
                    client.sse(urlString = "$baseUrl/v1/households/$householdId/events", request = { bearerAuth(token) }) {
                        incoming.collect { ev ->
                            when (ev.event) {
                                "ready" -> {
                                    _state.value = State.CONNECTED; _disconnectedSince.value = null; backoff = 1_000L
                                    Log.i(AuthRepository.TAG, "events ready")
                                    withContext(Dispatchers.Main) { onReady?.invoke() }
                                }
                                "change" -> ev.data?.let { data ->
                                    runCatching { HHJson.decodeFromString(ChangeEvent.serializer(), data) }
                                        .onSuccess { c -> withContext(Dispatchers.Main) { onChange?.invoke(c) } }
                                        .onFailure { Log.e(AuthRepository.TAG, "events: undecodable change frame") }
                                }
                            }
                        }
                    }
                }
                Log.i(AuthRepository.TAG, "events stream ended")
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                if (e is ApiException && e.status == 401) forceToken = true
                Log.e(AuthRepository.TAG, "events: ${e.message}")
            }
            _state.value = State.DISCONNECTED
            if (_disconnectedSince.value == null) _disconnectedSince.value = System.currentTimeMillis()
            delay(backoff)
            backoff = minOf(backoff * 2, 30_000L)
        }
    }
}
