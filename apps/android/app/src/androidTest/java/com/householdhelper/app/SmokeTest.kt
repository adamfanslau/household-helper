package com.householdhelper.app

import android.content.Intent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose smoke test on the dev flavor. Needs the local stack with a fresh seed and `adb reverse`
 * (scripts/dev/android.sh uitest sets nothing up itself; run `android.sh avd status` first).
 */
@RunWith(AndroidJUnit4::class)
class SmokeTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun signInAddAndSeeItem() {
        // The POST_NOTIFICATIONS prompt (first launch with a household) is a system window and
        // would hide the Compose hierarchy from the test; grant it up front.
        val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.grantRuntimePermission(instrumentation.targetContext.packageName, android.Manifest.permission.POST_NOTIFICATIONS)
        val intent = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java).putExtra("HH_UITEST_USER", "alice")
        ActivityScenario.launch<MainActivity>(intent).use {
            compose.waitUntil(20_000) { compose.onAllNodes(hasTestTag("list.item.Milk")).fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("list.item.Milk").assertIsDisplayed()
            compose.onNodeWithTag("list.input").performTextInput("Oat milk")
            compose.onNodeWithTag("list.add").performClick()
            // The new row lands in Unsorted at the bottom; with the keyboard up it is outside the lazy viewport.
            compose.waitUntil(10_000) {
                runCatching { compose.onNodeWithTag("list").performScrollToNode(hasTestTag("list.item.Oat milk")) }.isSuccess
            }
            compose.onNodeWithTag("list.item.Oat milk").assertIsDisplayed()
            compose.onNodeWithTag("tab.settings").performClick()
            compose.onNodeWithTag("settings.inviteCode").assertIsDisplayed()
        }
    }
}
