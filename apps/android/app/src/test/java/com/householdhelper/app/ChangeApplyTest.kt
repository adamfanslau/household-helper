package com.householdhelper.app

import com.householdhelper.app.data.ChangeEvent
import com.householdhelper.app.data.HHJson
import com.householdhelper.app.data.ListRepository
import com.householdhelper.app.data.ShoppingListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the Expo applyChange semantics: insert de-dupes by id, update replaces, delete removes. */
class ChangeApplyTest {
    private fun event(type: String, row: String) = HHJson.decodeFromString(ChangeEvent.serializer(),
        """{"id":"e","table":"shopping_list_items","type":"$type","row":$row,"actor":"dev-bob"}""")

    private fun row(id: String, name: String, status: String = "needed") = """
        {"id":"$id","household_id":"h","name":"$name","shop_id":null,"catalog_item_id":null,"quantity":null,
         "status":"$status","added_by":"dev-bob","created_at":"2026-01-01T10:00:00.000Z","updated_at":"2026-01-01T10:00:00.000Z",
         "bought_at":${if (status == "bought") "\"2026-01-01T10:00:00.000Z\"" else "null"}}""".trimIndent()

    @Test fun insertUpdateDelete() {
        var items = emptyList<ShoppingListItem>()
        items = ListRepository.applied(items, event("insert", row("a", "Milk")))
        items = ListRepository.applied(items, event("insert", row("a", "Milk"))) // echo of our own insert
        assertEquals(listOf("Milk"), items.map { it.name })
        items = ListRepository.applied(items, event("update", row("a", "Oat milk", "bought")))
        assertEquals("Oat milk", items.first().name); assertTrue(items.first().isBought)
        items = ListRepository.applied(items, event("delete", """{"id":"a"}"""))
        assertTrue(items.isEmpty())
        items = ListRepository.applied(items, event("delete", """{"id":"missing"}"""))
        assertTrue(items.isEmpty())
    }
}
