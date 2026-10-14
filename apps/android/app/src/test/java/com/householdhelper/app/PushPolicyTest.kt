package com.householdhelper.app

import com.householdhelper.app.data.PushRegistrar
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PushPolicyTest {
    @Test fun currentHouseholdInForegroundIsSilent() {
        assertFalse(PushRegistrar.shouldShow(foreground = true, currentHouseholdId = "h1", householdId = "h1"))
    }

    @Test fun otherHouseholdShows() {
        assertTrue(PushRegistrar.shouldShow(foreground = true, currentHouseholdId = "h1", householdId = "h2"))
    }

    @Test fun backgroundAlwaysShows() {
        assertTrue(PushRegistrar.shouldShow(foreground = false, currentHouseholdId = "h1", householdId = "h1"))
    }

    @Test fun missingHouseholdShows() {
        assertTrue(PushRegistrar.shouldShow(foreground = true, currentHouseholdId = "h1", householdId = null))
    }
}
