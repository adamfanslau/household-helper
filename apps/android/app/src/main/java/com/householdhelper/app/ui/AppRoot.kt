package com.householdhelper.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LoadingIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.HHJson
import com.householdhelper.app.data.Household
import com.householdhelper.app.ui.home.HomeScreen
import com.householdhelper.app.ui.onboarding.OnboardingScreen
import com.householdhelper.app.ui.signin.SignInScreen
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Gate: signed out → SignIn; no household → Onboarding; else Home. Owns the realtime connection
 * for the selected household and the app foreground/background lifecycle.
 */
@Composable
fun AppRoot(container: AppContainer) {
    val ready by container.auth.ready.collectAsStateWithLifecycle()
    val user by container.auth.user.collectAsStateWithLifecycle()
    val loaded by container.households.loaded.collectAsStateWithLifecycle()
    val current by container.households.current.collectAsStateWithLifecycle()

    LaunchedEffect(user?.uid) {
        container.push.authChanged(user?.uid)
        container.events.disconnect()
        container.households.reset()
        container.list.clear()
        if (user != null) container.households.load()
    }

    LaunchedEffect(loaded) { if (loaded) container.push.openPending() }

    LaunchedEffect(current?.id) {
        container.list.clear()
        val hid = current?.id
        if (hid == null) { container.events.disconnect(); return@LaunchedEffect }
        wire(container)
        container.events.connect(hid)
    }

    // Foreground: reconnect + refetch; background: drop the stream.
    DisposableEffect(Unit) {
        val owner = ProcessLifecycleOwner.get()
        val observer = LifecycleEventObserver { _, event ->
            val hid = container.households.current.value?.id ?: return@LifecycleEventObserver
            when (event) {
                Lifecycle.Event.ON_START -> {
                    wire(container); container.events.connect(hid)
                    CoroutineScope(Dispatchers.Main).launch { container.list.load(hid) }
                }
                Lifecycle.Event.ON_STOP -> container.events.disconnect()
                else -> {}
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
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

private fun wire(container: AppContainer) {
    container.events.onReady = { container.households.current.value?.let { container.list.load(it.id) } }
    container.events.onChange = { change ->
        if (change.table == "households") {
            runCatching { HHJson.decodeFromJsonElement(Household.serializer(), change.row) }.getOrNull()?.let { container.households.apply(it) }
        } else if (container.list.apply(change)) {
            CoroutineScope(Dispatchers.Main).launch { container.list.refresh() }
        }
    }
}
