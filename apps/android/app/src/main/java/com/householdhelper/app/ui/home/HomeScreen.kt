package com.householdhelper.app.ui.home

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.ui.list.ListScreen
import com.householdhelper.app.ui.settings.SettingsScreen
import com.householdhelper.app.ui.shops.ShopsScreen

enum class HomeTab(val label: String, val tag: String) { List("List", "tab.list"), Shops("Shops", "tab.shops"), Settings("Settings", "tab.settings") }

@Composable
fun HomeScreen(container: AppContainer) {
    var tab by rememberSaveable { mutableStateOf(HomeTab.List) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                HomeTab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t,
                        onClick = { tab = t },
                        icon = {
                            Icon(
                                when (t) { HomeTab.List -> Icons.Outlined.Checklist; HomeTab.Shops -> Icons.Outlined.Storefront; HomeTab.Settings -> Icons.Outlined.Settings },
                                contentDescription = null,
                            )
                        },
                        label = { Text(t.label) },
                        modifier = Modifier.testTag(t.tag),
                    )
                }
            }
        },
    ) { padding ->
        when (tab) {
            HomeTab.List -> ListScreen(container, Modifier.padding(padding))
            HomeTab.Shops -> ShopsScreen(container, Modifier.padding(padding))
            HomeTab.Settings -> SettingsScreen(container, Modifier.padding(padding))
        }
    }
}
