package com.householdhelper.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LoadingIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.ui.home.HomeScreen
import com.householdhelper.app.ui.onboarding.OnboardingScreen
import com.householdhelper.app.ui.signin.SignInScreen

/**
 * Gate: signed out → SignIn; no household → Onboarding; else Home. testTagsAsResourceId makes
 * every testTag visible to uiautomator (scripts/dev/android.sh tree).
 */
@Composable
fun AppRoot(container: AppContainer) {
    val ready by container.auth.ready.collectAsStateWithLifecycle()
    val user by container.auth.user.collectAsStateWithLifecycle()
    val loaded by container.households.loaded.collectAsStateWithLifecycle()
    val current by container.households.current.collectAsStateWithLifecycle()

    LaunchedEffect(user?.uid) {
        container.households.reset()
        container.list.clear()
        if (user != null) container.households.load()
    }

    Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
        when {
            !ready -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { LoadingIndicator(Modifier.testTag("loading")) }
            user == null -> SignInScreen(container.auth)
            !loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { LoadingIndicator(Modifier.testTag("loading")) }
            current == null -> OnboardingScreen(container, isSheet = false, onDone = {})
            else -> HomeScreen(container)
        }
    }
}
