package com.householdhelper.app

import com.householdhelper.app.data.ListGrouping
import com.householdhelper.app.data.Shop
import com.householdhelper.app.data.ShoppingListItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListGroupingTest {
    private val t = "2026-01-01T10:00:00.000Z"
    private fun shop(id: String, name: String, order: Int) = Shop(id, "h", name, order, t, t)
    private fun item(name: String, shop: String?, status: String = "needed") =
        ShoppingListItem(name, "h", name, shop, null, null, status, null, t, t, if (status == "bought") t else null)

    @Test fun groupsByShopOrderUnsortedLastBoughtSeparate() {
        val shops = listOf(shop("costco", "Costco", 1), shop("tj", "Trader Joe's", 0), shop("pharmacy", "Pharmacy", 2))
        val items = listOf(item("Milk", "tj"), item("Batteries", null), item("Towels", "costco"), item("Eggs", "tj", "bought"), item("Bananas", "tj"))
        val s = ListGrouping.sections(items, shops)
        assertEquals(listOf("Trader Joe's", "Costco", "Unsorted"), s.needed.map { it.title })
        assertEquals(listOf("Milk", "Bananas"), s.needed[0].items.map { it.name })
        assertNull(s.needed[2].shopId)
        assertEquals(listOf("Eggs"), s.bought.map { it.name })
    }

    @Test fun empty() {
        assertTrue(ListGrouping.sections(emptyList(), emptyList()).isEmpty)
    }
}
