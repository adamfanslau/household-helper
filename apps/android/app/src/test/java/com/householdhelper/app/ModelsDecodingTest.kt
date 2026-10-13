package com.householdhelper.app

import com.householdhelper.app.data.ApiErrorBody
import com.householdhelper.app.data.CatalogItem
import com.householdhelper.app.data.ChangeEvent
import com.householdhelper.app.data.HHJson
import com.householdhelper.app.data.Household
import com.householdhelper.app.data.Invite
import com.householdhelper.app.data.Me
import com.householdhelper.app.data.Shop
import com.householdhelper.app.data.ShoppingListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Decodes the API's golden fixtures (apps/api/internal/httpapi/testdata/golden, on the test resources path). */
class ModelsDecodingTest {
    private fun golden(name: String): String =
        checkNotNull(javaClass.classLoader?.getResource("$name.json")) { "missing fixture $name.json" }.readText()

    @Test fun me() {
        val m = HHJson.decodeFromString(Me.serializer(), golden("me"))
        assertEquals("dev-alice", m.id); assertEquals("Alice", m.displayName); assertEquals("password", m.provider)
    }

    @Test fun household() {
        val h = HHJson.decodeFromString(Household.serializer(), golden("household"))
        assertEquals("Mock Household", h.name); assertEquals("owner", h.role); assertEquals("dev-alice", h.createdBy)
    }

    @Test fun invite() {
        val i = HHJson.decodeFromString(Invite.serializer(), golden("invite"))
        assertEquals("MOCK1234", i.code); assertNull(i.revokedAt); assertNull(i.expiresAt)
    }

    @Test fun shop() {
        val s = HHJson.decodeFromString(Shop.serializer(), golden("shop"))
        assertEquals("Trader Joe's", s.name); assertEquals(0, s.sortOrder); assertEquals(2, s.neededCount)
    }

    @Test fun catalogItem() {
        val c = HHJson.decodeFromString(CatalogItem.serializer(), golden("catalog_item"))
        assertEquals("Milk", c.name); assertEquals("1 gal", c.defaultUnit)
    }

    @Test fun shoppingListItem() {
        val item = HHJson.decodeFromString(ShoppingListItem.serializer(), golden("shopping_list_item"))
        assertTrue(item.isBought); assertEquals("1 gal", item.quantity); assertNotNull(item.boughtAt); assertNotNull(item.shopId)
    }

    @Test fun sseChange() {
        val e = HHJson.decodeFromString(ChangeEvent.serializer(), golden("sse_change"))
        assertEquals("shopping_list_items", e.table); assertEquals("update", e.type); assertEquals("dev-bob", e.actor)
        val row = HHJson.decodeFromJsonElement(ShoppingListItem.serializer(), e.row)
        assertEquals("Milk", row.name); assertTrue(row.isBought)
    }

    @Test fun errorEnvelope() {
        val e = HHJson.decodeFromString(ApiErrorBody.serializer(), golden("error"))
        assertEquals("invalid_request", e.error.code); assertNotNull(e.error.fields?.get("name"))
    }
}
