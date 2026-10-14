package com.householdhelper.app.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ToggleButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.householdhelper.app.data.AppContainer
import kotlinx.coroutines.launch

/** Create or join a household. Full screen on first run; a sheet from Settings (isSheet). */
@Composable
fun OnboardingScreen(container: AppContainer, isSheet: Boolean, onDone: () -> Unit, initialJoin: Boolean = false, initialCode: String? = null) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var join by remember { mutableStateOf(initialJoin || initialCode != null) }
    var input by remember { mutableStateOf(initialCode ?: "") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val value = input.trim()
        if (value.isEmpty() || busy) return
        scope.launch {
            busy = true
            runCatching {
                if (join) container.households.join(value.uppercase()) else container.households.create(value)
            }.onSuccess { input = ""; error = null; container.router.tab.value = com.householdhelper.app.data.AppRouter.Tab.LIST; onDone() }.onFailure { error = it.message }
            busy = false
        }
    }

    Column(Modifier.then(if (isSheet) Modifier.fillMaxWidth() else Modifier.fillMaxSize().systemBarsPadding()).padding(24.dp)) {
        Text(if (isSheet) "Another household" else "Welcome", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(16.dp))
        // Expressive connected button group as the Create / Join switch.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)) {
            ToggleButton(checked = !join, onCheckedChange = { join = false }, modifier = Modifier.weight(1f).testTag("onboarding.mode.create"),
                shapes = ButtonGroupDefaults.connectedLeadingButtonShapes()) { Text("Create") }
            ToggleButton(checked = join, onCheckedChange = { join = true }, modifier = Modifier.weight(1f).testTag("onboarding.mode.join"),
                shapes = ButtonGroupDefaults.connectedTrailingButtonShapes()) { Text("Join") }
        }
        Spacer(Modifier.height(16.dp))
        OutlinedTextField(
            value = input,
            onValueChange = { input = if (join) it.uppercase().take(8) else it },
            label = { Text(if (join) "Invite code (e.g. AB12CD34)" else "Household name") },
            singleLine = true,
            textStyle = if (join) MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace) else MaterialTheme.typography.bodyLarge,
            keyboardOptions = KeyboardOptions(capitalization = if (join) KeyboardCapitalization.Characters else KeyboardCapitalization.Words, imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = { submit() }),
            supportingText = { Text(error ?: if (join) "Enter the 8-character code from a household member." else "Start a household and invite others with its code.") },
            isError = error != null,
            modifier = Modifier.fillMaxWidth().testTag("onboarding.input"),
        )
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = { submit() },
            enabled = !busy && input.isNotBlank(),
            shapes = ButtonDefaults.shapes(),
            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("onboarding.submit"),
        ) { Text(if (join) "Join household" else "Create household") }
        if (!isSheet) Spacer(Modifier.weight(1f)) else Spacer(Modifier.height(16.dp))
        if (!isSheet) {
            TextButton(onClick = { scope.launch { container.auth.signOut(context) } }, modifier = Modifier.testTag("settings.signOut")) { Text("Sign out") }
        }
    }
}
