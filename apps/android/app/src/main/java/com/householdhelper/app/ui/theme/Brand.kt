package com.householdhelper.app.ui.theme

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.LocalPharmacy
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.ShoppingBasket
import androidx.compose.material.icons.filled.WineBar
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The app's visual language: one brand green, a stable colour + icon per shop (same hash as iOS
 * Brand.swift so a shop looks the same on both phones).
 */
object Brand {
    val Primary = Color(0xFF17A06A)
    val PrimaryDeep = Color(0xFF0E6B47)
    val Mint = Color(0xFFC8F2DD)
    val Basket = Color(0xFF21B873)
    val MintBright = Color(0xFF6FD9A6)   // the mark's roof/spark on dark
    val Ink = Color(0xFF10201A)          // the mark's dark tile
    val InkSoft = Color(0xFF1E3A2C)

    val ShopPalette = listOf(
        Color(0xFFF26B5B), // coral
        Color(0xFFF2A33A), // amber
        Color(0xFF8CC24A), // lime
        Color(0xFF1FB5A3), // teal
        Color(0xFF3B9EE8), // sky
        Color(0xFF8E6BE8), // violet
        Color(0xFFEC5FA3), // pink
        Color(0xFF6B7A8F), // slate
    )

    /** Same arithmetic as iOS: sum of the lower-cased code points mod 8. */
    fun shopColor(name: String): Color {
        var sum = 0
        name.lowercase().codePoints().forEach { sum = (sum + it) % 100_000 }
        return ShopPalette[sum % ShopPalette.size]
    }

    fun shopIcon(name: String): ImageVector {
        val n = name.lowercase()
        return when {
            listOf("pharm", "drug", "apothe", "boots").any { it in n } -> Icons.Filled.LocalPharmacy
            listOf("costco", "wholesale", "bulk", "warehouse").any { it in n } -> Icons.Filled.Inventory2
            listOf("bak", "bread").any { it in n } -> Icons.Filled.Cake
            listOf("hardware", "diy", "depot", "ikea").any { it in n } -> Icons.Filled.Build
            "pet" in n -> Icons.Filled.Pets
            listOf("farm", "market", "veg", "fruit").any { it in n } -> Icons.Filled.Eco
            listOf("butcher", "meat").any { it in n } -> Icons.Filled.Restaurant
            listOf("wine", "off licence", "liquor").any { it in n } -> Icons.Filled.WineBar
            else -> Icons.Filled.ShoppingBasket
        }
    }
}
