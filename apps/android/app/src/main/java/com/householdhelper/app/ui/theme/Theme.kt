package com.householdhelper.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.expressiveLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Branded palette instead of wallpaper-derived dynamic colour: the list is the product, and the
// brand green plus per-shop colours (Brand.kt) carry the identity on both platforms.
// Expressive surface kept small on purpose (theme + motion + a few components).
private val Light = expressiveLightColorScheme().copy(
    primary = Brand.Primary,
    onPrimary = Color.White,
    primaryContainer = Brand.Mint,
    onPrimaryContainer = Color(0xFF003822),
    secondary = Color(0xFF4A6354),
    secondaryContainer = Color(0xFFD6EADB),
    onSecondaryContainer = Color(0xFF0A2015),
    tertiary = Color(0xFF2F6F8F),
    tertiaryContainer = Color(0xFFCFE6F8),
    onTertiaryContainer = Color(0xFF07293C),
    surface = Color(0xFFF7FAF8),
    surfaceContainerLow = Color(0xFFF0F5F2),
    surfaceContainer = Color(0xFFEAF1EC),
    surfaceContainerHigh = Color(0xFFE3ECE6),
    background = Color(0xFFF7FAF8),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF6FD9A6),
    onPrimary = Color(0xFF003822),
    primaryContainer = Color(0xFF0E6B47),
    onPrimaryContainer = Brand.Mint,
    secondary = Color(0xFFB4CCBB),
    secondaryContainer = Color(0xFF324A3B),
    onSecondaryContainer = Color(0xFFD6EADB),
    tertiary = Color(0xFF9DCDEB),
    tertiaryContainer = Color(0xFF1E4D68),
    onTertiaryContainer = Color(0xFFCFE6F8),
    surface = Color(0xFF101513),
    surfaceContainerLow = Color(0xFF171D1A),
    surfaceContainer = Color(0xFF1C2320),
    surfaceContainerHigh = Color(0xFF242C28),
    background = Color(0xFF101513),
)

@Composable
fun HouseholdHelperTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialExpressiveTheme(
        colorScheme = if (darkTheme) Dark else Light,
        motionScheme = MotionScheme.expressive(),
        content = content,
    )
}
