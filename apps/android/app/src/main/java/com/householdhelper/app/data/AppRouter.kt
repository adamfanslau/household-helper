package com.householdhelper.app.data

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow

/** Tab selection, Shops back stack and deep links: householdhelper://list | shops | shops/<id> | household (alias settings) | join/<CODE>. */
class AppRouter {
    enum class Tab { LIST, SHOPS, HOUSEHOLD }

    val tab = MutableStateFlow(Tab.LIST)
    /** Shop id to open in the Shops tab (consumed by ShopsScreen). */
    val openShopId = MutableStateFlow<String?>(null)
    /** Code from a join link; the join sheet consumes it. */
    val pendingJoinCode = MutableStateFlow<String?>(null)

    fun handle(uri: Uri): Boolean {
        if (uri.scheme != "householdhelper") return false
        val parts = listOfNotNull(uri.host) + uri.pathSegments
        when (parts.firstOrNull()) {
            "list" -> tab.value = Tab.LIST
            "shops" -> { tab.value = Tab.SHOPS; openShopId.value = parts.getOrNull(1) }
            "settings", "household" -> tab.value = Tab.HOUSEHOLD
            "join" -> { val code = parts.getOrNull(1) ?: return false; pendingJoinCode.value = code.uppercase() }
            else -> return false
        }
        return true
    }
}
