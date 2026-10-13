package com.householdhelper.app.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import kotlinx.coroutines.launch

/** Android A1 subset: household, account, switch household, sign out. Invite + share come in A2. */
@Composable
fun SettingsScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val households by container.households.households.collectAsStateWithLifecycle()
    val current by container.households.current.collectAsStateWithLifecycle()

    Scaffold(modifier = modifier, topBar = { TopAppBar(title = { Text("Settings") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Text("Household", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(16.dp, 8.dp))
            ListItem(headlineContent = { Text("Name") }, trailingContent = { Text(current?.name ?: "—") })
            ListItem(headlineContent = { Text("Signed in as") }, trailingContent = { Text(container.auth.email ?: "—", modifier = Modifier.testTag("settings.email")) })
            if (households.size > 1) {
                HorizontalDivider()
                Text("Switch household", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(16.dp, 8.dp))
                households.forEach { h ->
                    ListItem(
                        headlineContent = { Text(h.name) },
                        trailingContent = { if (h.id == current?.id) Icon(Icons.Outlined.Check, contentDescription = "selected", tint = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.fillMaxWidth().clickable { scope.launch { container.households.select(h) } }.testTag("settings.household.${h.name}"),
                    )
                }
            }
            HorizontalDivider()
            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                TextButton(onClick = { container.auth.signOut() }, modifier = Modifier.testTag("settings.signOut")) {
                    Text("Sign out", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}
