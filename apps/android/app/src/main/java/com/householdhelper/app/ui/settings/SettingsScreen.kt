package com.householdhelper.app.ui.settings

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import com.householdhelper.app.data.PushRegistrar
import androidx.compose.ui.Modifier
import com.householdhelper.app.ui.exposeTestTags
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.BuildConfig
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.ui.onboarding.JoinSheet
import kotlinx.coroutines.launch

fun shareInvite(context: Context, code: String, household: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, "Join our household \"$household\" in Household Helper. Invite code: $code")
    }
    context.startActivity(Intent.createChooser(send, "Share invite"))
}

@Composable
fun SettingsScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val households by container.households.households.collectAsStateWithLifecycle()
    val current by container.households.current.collectAsStateWithLifecycle()
    val invites by container.households.invites.collectAsStateWithLifecycle()
    var showAdd by remember { mutableStateOf(false) }
    var confirmSignOut by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    val code = invites.firstOrNull { it.revokedAt == null }?.code

    Scaffold(modifier = modifier, topBar = { TopAppBar(title = { Text("Settings") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            SectionLabel("Household")
            ListItem(headlineContent = { Text("Name") }, trailingContent = { Text(current?.name ?: "—") },
                modifier = Modifier.clickable { newName = current?.name ?: ""; renaming = true }.testTag("settings.name"))
            ListItem(headlineContent = { Text("Signed in as") }, trailingContent = { Text(container.auth.email ?: "—", modifier = Modifier.testTag("settings.email")) })

            SectionLabel("Invite code")
            Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        code ?: "…",
                        style = MaterialTheme.typography.displayMedium.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, letterSpacing = 6.sp),
                        modifier = Modifier.semantics { contentDescription = "Invite code ${code?.toList()?.joinToString(" ") ?: ""}" }.testTag("settings.inviteCode"),
                    )
                    Text("Share this so others can join and see the same list.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
                    Button(onClick = { code?.let { shareInvite(context, it, current?.name ?: "") } }, enabled = code != null, shapes = ButtonDefaults.shapes(),
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp).testTag("settings.share")) {
                        Icon(Icons.Outlined.Share, null); Text("  Share invite")
                    }
                    TextButton(onClick = { scope.launch { container.households.regenerateInvite() } }, modifier = Modifier.testTag("settings.regenerate")) {
                        Icon(Icons.Outlined.Refresh, null); Text("  Regenerate code")
                    }
                }
            }

            if (households.size > 1) {
                SectionLabel("Switch household")
                households.forEach { h ->
                    ListItem(
                        headlineContent = { Text(h.name) },
                        trailingContent = { if (h.id == current?.id) Icon(Icons.Outlined.Check, contentDescription = "selected", tint = MaterialTheme.colorScheme.primary) },
                        modifier = Modifier.fillMaxWidth().clickable { scope.launch { container.households.select(h) } }.testTag("settings.household.${h.name}"),
                    )
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            ListItem(headlineContent = { Text("Create or join another household") }, leadingContent = { Icon(Icons.Outlined.Add, null) },
                modifier = Modifier.clickable { showAdd = true }.testTag("settings.addHousehold"))

            SectionLabel("Notifications")
            val pushStatus by container.push.status.collectAsStateWithLifecycle()
            val askPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { container.push.permissionResult(it) }
            when (pushStatus) {
                PushRegistrar.Status.AUTHORIZED -> ListItem(headlineContent = { Text("Notifications") }, supportingContent = { Text("Hear when someone adds to the list or joins.") },
                    trailingContent = { Text("On") }, modifier = Modifier.testTag("settings.notifications"))
                PushRegistrar.Status.DENIED -> ListItem(headlineContent = { Text("Notifications are off") }, supportingContent = { Text("Turn them on in system settings.") },
                    leadingContent = { Icon(Icons.Outlined.NotificationsOff, null) },
                    modifier = Modifier.clickable {
                        context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
                    }.testTag("settings.notifications"))
                PushRegistrar.Status.NOT_ASKED -> ListItem(headlineContent = { Text("Enable notifications") }, supportingContent = { Text("Hear when someone adds to the list or joins.") },
                    leadingContent = { Icon(Icons.Outlined.Notifications, null) },
                    modifier = Modifier.clickable { askPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS) }.testTag("settings.notifications"))
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp))

            SectionLabel("About")
            ListItem(headlineContent = { Text("Version") }, trailingContent = { Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})") })
            ListItem(headlineContent = { Text("Server") }, trailingContent = { Text(BuildConfig.API_BASE_URL.removePrefix("https://").removePrefix("http://")) })

            HorizontalDivider(Modifier.padding(vertical = 8.dp))
            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                TextButton(onClick = { confirmSignOut = true }, modifier = Modifier.testTag("settings.signOut")) {
                    Text("Sign out", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (showAdd) JoinSheet(container, code = null, onDismiss = { showAdd = false })
    if (renaming) AlertDialog(
        modifier = Modifier.exposeTestTags(),
        onDismissRequest = { renaming = false }, title = { Text("Rename household") },
        text = { OutlinedTextField(newName, { newName = it }, singleLine = true, modifier = Modifier.testTag("settings.rename.input")) },
        confirmButton = { TextButton(onClick = { renaming = false; scope.launch { container.households.rename(newName) } }) { Text("Save") } },
        dismissButton = { TextButton(onClick = { renaming = false }) { Text("Cancel") } },
    )
    if (confirmSignOut) AlertDialog(
        modifier = Modifier.exposeTestTags(),
        onDismissRequest = { confirmSignOut = false }, title = { Text("Sign out of Household Helper?") },
        text = { Text("Your lists stay in the household; sign back in any time.") },
        confirmButton = { TextButton(onClick = { confirmSignOut = false; scope.launch { container.auth.signOut(context) } }, modifier = Modifier.testTag("settings.signOut.confirm")) { Text("Sign out", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text("Cancel") } },
    )
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(16.dp, 12.dp, 16.dp, 4.dp))
}
