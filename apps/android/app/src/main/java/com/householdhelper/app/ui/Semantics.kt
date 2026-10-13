package com.householdhelper.app.ui

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId

/**
 * Sheets, dialogs and popups live in their own windows, outside the root that already exposes
 * test tags; uiautomator (scripts/dev/android.sh) sees their tags only if each window opts in.
 */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.exposeTestTags(): Modifier = semantics { testTagsAsResourceId = true }
