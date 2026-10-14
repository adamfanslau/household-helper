package com.householdhelper.app.ui.signin

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.householdhelper.app.BuildConfig
import com.householdhelper.app.data.AuthRepository
import kotlinx.coroutines.launch

@Composable
fun SignInScreen(auth: AuthRepository) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val googleAvailable = BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotEmpty()

    Column(
        Modifier.fillMaxSize().systemBarsPadding().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Icon(Icons.Outlined.ShoppingCart, contentDescription = null, Modifier.size(72.dp), tint = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(16.dp))
        Text("Household Helper", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(8.dp))
        Text("One shopping list for the whole home.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))

        Button(
            onClick = {
                scope.launch {
                    busy = true; error = null
                    runCatching { auth.signInWithGoogle(context) }
                        .onFailure { if (it !is AuthRepository.SignInCancelled) error = it.message ?: "Sign-in failed" }
                    busy = false
                }
            },
            enabled = !busy && googleAvailable,
            shapes = ButtonDefaults.shapes(),
            modifier = Modifier.fillMaxWidth().height(52.dp).testTag("signin.google"),
        ) { Text("Continue with Google") }

        if (!googleAvailable && !BuildConfig.DEV_LOGIN) {
            Spacer(Modifier.height(8.dp))
            Text("Google sign-in is not configured for this build.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        if (BuildConfig.DEV_LOGIN) {
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (who in listOf("alice", "bob")) {
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                busy = true
                                runCatching { auth.signInDev(who) }.onFailure { error = it.message }
                                busy = false
                            }
                        },
                        enabled = !busy,
                        shapes = ButtonDefaults.shapes(),
                        modifier = Modifier.weight(1f).testTag("signin.dev.$who"),
                    ) { Text("Sign in as ${who.replaceFirstChar { it.uppercase() }}") }
                }
            }
            Spacer(Modifier.height(8.dp))
            Text("Dev build: Firebase Auth emulator", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
        error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.height(16.dp))
    }
}
