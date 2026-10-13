package com.householdhelper.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
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
        handleUiTestUser(intent)
    }

    /** `adb shell am start … --es HH_UITEST_USER alice`: dev flavor only; switches users if needed. */
    private fun handleUiTestUser(intent: Intent?) {
        if (!BuildConfig.DEV_LOGIN) return
        val who = intent?.getStringExtra("HH_UITEST_USER")?.takeIf { it.isNotBlank() } ?: return
        val auth = container.auth
        lifecycleScope.launch {
            if (auth.email != "$who@dev.local") {
                if (auth.uid != null) auth.signOut()
                runCatching { withTimeout(20_000) { auth.signInDev(who) } }
                    .onSuccess { Log.i("HH", "dev sign-in as $who ok") }
                    .onFailure { Log.e("HH", "dev sign-in as $who failed: ${it.message}") }
            }
        }
    }
}
