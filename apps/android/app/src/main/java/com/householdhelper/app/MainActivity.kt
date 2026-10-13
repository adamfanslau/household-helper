package com.householdhelper.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.householdhelper.app.ui.AppRoot
import com.householdhelper.app.ui.theme.HouseholdHelperTheme
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleUiTestUser(intent)
        setContent {
            HouseholdHelperTheme {
                AppRoot(container = (application as HHApplication).container)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleUiTestUser(intent)
    }

    /** `adb shell am start … --es HH_UITEST_USER alice`: dev flavor only; switches users if needed. */
    private fun handleUiTestUser(intent: Intent?) {
        if (!BuildConfig.DEV_LOGIN) return
        val who = intent?.getStringExtra("HH_UITEST_USER")?.takeIf { it.isNotBlank() }
        Log.i("HH", "uitest user extra: ${who ?: "none"}")
        who ?: return
        val auth = (application as HHApplication).container.auth
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
