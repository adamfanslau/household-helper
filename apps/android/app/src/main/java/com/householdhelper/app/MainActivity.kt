package com.householdhelper.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.householdhelper.app.data.PushRegistrar
import com.householdhelper.app.ui.AppRoot
import com.householdhelper.app.ui.theme.HouseholdHelperTheme
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

class MainActivity : ComponentActivity() {
    private val container get() = (application as HHApplication).container

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Only on a fresh start: after a configuration change the Activity is recreated with the same
        // intent, and re-handling a deep link would yank the user back to that screen.
        if (savedInstanceState == null) handleIntent(intent)
        setContent {
            HouseholdHelperTheme {
                AppRoot(container = container)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.data?.let { if (container.router.handle(it)) Log.i("HH", "deep link $it") }
        // A notification tap (FCM puts the data keys on the launcher intent; our own foreground
        // notifications use the same extras).
        intent?.getStringExtra(PushRegistrar.EXTRA_HOUSEHOLD_ID)?.let { container.push.open(it) }
        handleUiTestUser(intent)
        handleFakePush(intent)
    }

    /** `--es HH_FAKE_PUSH "<household_id>~<title>~<body>"` (adb's shell would eat `|`): dev flavor only; drives the foreground handling without FCM. */
    private fun handleFakePush(intent: Intent?) {
        if (!BuildConfig.DEV_LOGIN) return
        val spec = intent?.getStringExtra("HH_FAKE_PUSH")?.takeIf { it.isNotBlank() } ?: return
        val parts = spec.split("~")
        container.push.handleMessage(parts.getOrNull(0), "shopping_list_items.insert", parts.getOrNull(1), parts.getOrNull(2))
    }

    /** `adb shell am start … --es HH_UITEST_USER alice`: dev flavor only; switches users if needed. */
    private fun handleUiTestUser(intent: Intent?) {
        if (!BuildConfig.DEV_LOGIN) return
        val who = intent?.getStringExtra("HH_UITEST_USER")?.takeIf { it.isNotBlank() } ?: return
        val auth = container.auth
        lifecycleScope.launch {
            if (auth.email != "$who@dev.local") {
                if (auth.uid != null) auth.signOut()  // suspend: waits for the push token removal
                runCatching { withTimeout(20_000) { auth.signInDev(who) } }
                    .onSuccess { Log.i("HH", "dev sign-in as $who ok") }
                    .onFailure { Log.e("HH", "dev sign-in as $who failed: ${it.message}") }
            }
        }
    }
}
