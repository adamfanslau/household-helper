package com.householdhelper.app.ui.onboarding

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.householdhelper.app.ui.exposeTestTags
import androidx.compose.ui.platform.testTag
import com.householdhelper.app.data.AppContainer

/** Create-or-join as a bottom sheet (Settings, or a householdhelper://join/<CODE> link). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JoinSheet(container: AppContainer, code: String?, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, modifier = Modifier.testTag("onboarding.sheet").exposeTestTags()) {
        OnboardingScreen(container, isSheet = true, onDone = onDismiss, initialJoin = code != null, initialCode = code)
    }
}
