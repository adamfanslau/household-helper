package com.householdhelper.app.data

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.firebase.messaging.FirebaseMessaging
import com.householdhelper.app.BuildConfig
import com.householdhelper.app.MainActivity
import com.householdhelper.app.R
import io.ktor.client.request.setBody
import io.ktor.http.HttpMethod
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Push: notification channel + permission state, FCM token → PUT /v1/me/push-tokens (removed
 * before sign-out), and what an incoming message does: no banner for the household on screen
 * (SSE already updated it), a tap switches to the household. The dev flavor never registers with
 * FCM (fabricated project; auto-init is off in its manifest) — `HH_FAKE_PUSH` drives the handling.
 */
class PushRegistrar(
    private val context: Context,
    private val api: ApiClient,
    private val households: HouseholdRepository,
    private val router: AppRouter,
) {
    enum class Status { NOT_ASKED, AUTHORIZED, DENIED }

    private val _status = MutableStateFlow(Status.NOT_ASKED)
    val status: StateFlow<Status> = _status
    private val prefs = context.getSharedPreferences("push", Context.MODE_PRIVATE)
    private val scope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }
    private var fcmToken: String? = null
    private var uploadedToken: String? = null
    private var signedInUid: String? = null
    /** Household a notification tap asked for before the households were loaded. */
    private var pendingHouseholdId: String? = null

    init {
        refreshStatus()
    }

    fun ensureChannel() {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Household", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Someone added to the list or joined"
        })
    }

    fun refreshStatus() {
        _status.value = when {
            Build.VERSION.SDK_INT < 33 -> if (NotificationManagerCompat.from(context).areNotificationsEnabled()) Status.AUTHORIZED else Status.DENIED
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED -> Status.AUTHORIZED
            prefs.getBoolean("asked", false) -> Status.DENIED
            else -> Status.NOT_ASKED
        }
    }

    /** The system prompt is asked once a household exists; the UI launches it, this records it. */
    fun shouldAsk(): Boolean = Build.VERSION.SDK_INT >= 33 && _status.value == Status.NOT_ASKED

    fun permissionResult(granted: Boolean) {
        prefs.edit().putBoolean("asked", true).apply()
        refreshStatus()
        Log.i(AuthRepository.TAG, "notification permission: ${if (granted) "granted" else "denied"}")
    }

    // --- token ---

    fun authChanged(uid: String?) {
        signedInUid = uid
        if (uid == null) { uploadedToken = null; return }
        if (!BuildConfig.PUSH_ENABLED) { Log.i(AuthRepository.TAG, "fcm registration skipped (dev build)"); return }
        scope.launch {
            runCatching { FirebaseMessaging.getInstance().token.await() }
                .onSuccess { onToken(it) }
                .onFailure { Log.w(AuthRepository.TAG, "fcm token failed: ${it.message}") }
        }
    }

    /** From the messaging service (rotation) or the initial fetch. */
    fun onToken(token: String) {
        fcmToken = token
        scope.launch { upload() }
    }

    private suspend fun upload() {
        val token = fcmToken ?: return
        if (signedInUid == null || token == uploadedToken) return
        runCatching { api.call(HttpMethod.Put, "/v1/me/push-tokens") { setBody(mapOf("token" to token, "platform" to "android")) } }
            .onSuccess { uploadedToken = token; Log.i(AuthRepository.TAG, "push token registered") }
            .onFailure { Log.w(AuthRepository.TAG, "push token upload failed: ${it.message}") }
    }

    /** Before sign-out, while the ID token still works. */
    suspend fun unregister() {
        val token = uploadedToken ?: fcmToken ?: return
        runCatching { api.delete("/v1/me/push-tokens/$token") }
            .onSuccess { Log.i(AuthRepository.TAG, "push token removed") }
            .onFailure { Log.w(AuthRepository.TAG, "push token removal failed: ${it.message}") }
        uploadedToken = null
    }

    // --- incoming ---

    /** Foreground delivery from the service (or HH_FAKE_PUSH in dev): post unless that household is on screen. */
    fun handleMessage(householdId: String?, type: String, title: String?, body: String?) {
        val foreground = ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
        if (!shouldShow(foreground, households.current.value?.id, householdId)) {
            Log.i(AuthRepository.TAG, "suppressed push for the current household $householdId")
            return
        }
        if (_status.value != Status.AUTHORIZED) return
        val tap = PendingIntent.getActivity(
            context, (householdId ?: "").hashCode(),
            Intent(context, MainActivity::class.java).putExtra(EXTRA_HOUSEHOLD_ID, householdId).putExtra(EXTRA_TYPE, type)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title ?: "Household Helper")
            .setContentText(body ?: "")
            .setGroup("hh-${householdId ?: ""}")
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify((householdId ?: "").hashCode(), n) }
            .onSuccess { Log.i(AuthRegistrarTag, "posted push for $householdId") }
            .onFailure { Log.w(AuthRepository.TAG, "post notification failed: ${it.message}") }
    }

    /** Tap: switch to that household's list (deferred until the households are loaded). */
    fun open(householdId: String?) {
        pendingHouseholdId = householdId?.takeIf { it.isNotBlank() } ?: return
        openPending()
    }

    fun openPending() {
        val hid = pendingHouseholdId ?: return
        if (!households.loaded.value) return
        pendingHouseholdId = null
        val h = households.households.value.firstOrNull { it.id == hid }
        if (h == null) { Log.i(AuthRepository.TAG, "push tap for an unknown household $hid"); return }
        scope.launch {
            if (households.current.value?.id != hid) households.select(h)
            router.tab.value = AppRouter.Tab.LIST
            Log.i(AuthRepository.TAG, "opened household $hid from a push")
        }
    }

    companion object {
        const val CHANNEL_ID = "household"
        const val EXTRA_HOUSEHOLD_ID = "household_id"
        const val EXTRA_TYPE = "type"
        private const val AuthRegistrarTag = AuthRepository.TAG

        /** Pure policy: the household on screen is already live over SSE. */
        fun shouldShow(foreground: Boolean, currentHouseholdId: String?, householdId: String?): Boolean =
            !(foreground && householdId != null && householdId == currentHouseholdId)
    }
}
