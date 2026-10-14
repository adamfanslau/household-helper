package com.householdhelper.app.ui.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.AppRouter
import com.householdhelper.app.ui.list.ListScreen
import com.householdhelper.app.ui.onboarding.JoinSheet
import com.householdhelper.app.ui.settings.SettingsScreen
import com.householdhelper.app.ui.shops.ShopsScreen
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay

@Composable
fun HomeScreen(container: AppContainer) {
    val tab by container.router.tab.collectAsStateWithLifecycle()
    val joinCode by container.router.pendingJoinCode.collectAsStateWithLifecycle()
    // Ask for notifications only once there is a household to be notified about.
    val askPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { container.push.permissionResult(it) }
    LaunchedEffect(Unit) { if (container.push.shouldAsk()) askPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS) }
    Box(Modifier.fillMaxSize()) {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    AppRouter.Tab.entries.forEach { t ->
                        NavigationBarItem(
                            selected = tab == t,
                            onClick = { container.router.tab.value = t },
                            icon = {
                                Icon(
                                    when (t) { AppRouter.Tab.LIST -> Icons.Outlined.Checklist; AppRouter.Tab.SHOPS -> Icons.Outlined.Storefront; AppRouter.Tab.SETTINGS -> Icons.Outlined.Settings },
                                    contentDescription = null,
                                )
                            },
                            label = { Text(when (t) { AppRouter.Tab.LIST -> "List"; AppRouter.Tab.SHOPS -> "Shops"; AppRouter.Tab.SETTINGS -> "Settings" }) },
                            modifier = Modifier.testTag("tab.${t.name.lowercase()}"),
                        )
                    }
                }
            },
        ) { padding ->
            when (tab) {
                AppRouter.Tab.LIST -> ListScreen(container, Modifier.padding(padding))
                AppRouter.Tab.SHOPS -> ShopsScreen(container, Modifier.padding(padding))
                AppRouter.Tab.SETTINGS -> SettingsScreen(container, Modifier.padding(padding))
            }
        }
        ConnectionPill(container, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp))
        if (joinCode != null) {
            JoinSheet(container, code = joinCode, onDismiss = { container.router.pendingJoinCode.value = null })
        }
    }
}

/** "Reconnecting…" after 3 s without a stream; hidden as soon as `ready` arrives. */
@Composable
fun ConnectionPill(container: AppContainer, modifier: Modifier = Modifier) {
    val state by container.events.state.collectAsStateWithLifecycle()
    val since by container.events.disconnectedSince.collectAsStateWithLifecycle()
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(state, since) {
        show = false
        if (since != null && state != com.householdhelper.app.data.EventsClient.State.CONNECTED) {
            delay(maxOf(0L, 3_000 - (System.currentTimeMillis() - since!!)))
            show = true
        }
    }
    AnimatedVisibility(show, modifier, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
        Surface(shape = MaterialTheme.shapes.extraLarge, tonalElevation = 3.dp, shadowElevation = 2.dp, modifier = Modifier.testTag("connection.reconnecting")) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.WifiOff, contentDescription = null, Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Reconnecting…", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}
