// Wire models for hh-api (apps/api/API.md); shapes pinned by the golden fixtures decoded in
// ModelsDecodingTest. Timestamps stay ISO-8601 strings; parse with java.time.Instant when needed.
package com.householdhelper.app.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNamingStrategy

val HHJson: Json = Json {
    namingStrategy = JsonNamingStrategy.SnakeCase
    ignoreUnknownKeys = true
    explicitNulls = false   // omit nulls in request bodies; PATCH "clear" uses explicit JsonNull
    coerceInputValues = true
}

@Serializable
data class Me(val id: String, val email: String, val displayName: String, val provider: String, val createdAt: String, val lastSeenAt: String)

@Serializable
data class Household(
    val id: String,
    val name: String,
    val createdBy: String? = null,
    val createdAt: String,
    val updatedAt: String,
    val role: String? = null,
)

@Serializable
data class Invite(
    val id: String,
    val householdId: String,
    val code: String,
    val createdBy: String? = null,
    val createdAt: String,
    val expiresAt: String? = null,
    val revokedAt: String? = null,
)

@Serializable
data class Shop(
    val id: String,
    val householdId: String,
    val name: String,
    val sortOrder: Int,
    val createdAt: String,
    val updatedAt: String,
    val neededCount: Int = 0,
)

@Serializable
data class CatalogItem(
    val id: String,
    val householdId: String,
    val shopId: String? = null,   // last shop used (hint)
    val name: String,
    val defaultUnit: String? = null,
    val createdAt: String,
    val updatedAt: String,
)

@Serializable
data class ShoppingListItem(
    val id: String,
    val householdId: String,
    val name: String,
    val shopId: String? = null,
    val catalogItemId: String? = null,
    val quantity: String? = null,
    val status: String,
    val addedBy: String? = null,
    val createdAt: String,
    val updatedAt: String,
    val boughtAt: String? = null,
) {
    val isBought: Boolean get() = status == "bought"
    /** Ticked in the shop, not yet checked out. */
    val isInBasket: Boolean get() = status == "in_basket"
}

/** One `event: change` frame; `row` is decoded per table. */
@Serializable
data class ChangeEvent(val id: String, val table: String, val type: String, val row: JsonElement, val actor: String)

@Serializable
data class ApiErrorBody(val error: Detail) {
    @Serializable
    data class Detail(val code: String, val message: String, val fields: Map<String, String>? = null)
}

class ApiException(val status: Int, val code: String, override val message: String) : Exception(message)
