package com.householdhelper.app.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.householdhelper.app.ui.theme.Brand

/** Round coloured badge with an icon: the shop's identity, used in headers, rows and cards. */
@Composable
fun ShopGlyph(name: String?, size: Dp = 32.dp, modifier: Modifier = Modifier) {
    val color = name?.let { Brand.shopColor(it) } ?: MaterialTheme.colorScheme.outline
    Box(
        modifier.size(size).background(Brush.linearGradient(listOf(color, color.copy(alpha = 0.75f))), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(name?.let { Brand.shopIcon(it) } ?: Icons.Filled.Inbox, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.5f))
    }
}

/** The tick: hollow ring in the shop's colour, filled green when in the basket, muted when bought. */
@Composable
fun CheckMark(status: String, tint: Color, modifier: Modifier = Modifier) {
    AnimatedContent(targetState = status, transitionSpec = { (scaleIn() togetherWith scaleOut()) }, label = "tick", modifier = modifier.size(28.dp)) { s ->
        when (s) {
            "needed" -> Box(Modifier.size(28.dp).border(2.dp, tint.copy(alpha = 0.55f), CircleShape))
            "in_basket" -> Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Brand.Basket, modifier = Modifier.size(28.dp))
            else -> Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(28.dp))
        }
    }
}

/** Small rounded chip for quantities and counts. */
@Composable
fun Chip(text: String, tint: Color = MaterialTheme.colorScheme.primary, modifier: Modifier = Modifier) {
    Surface(shape = CircleShape, color = tint.copy(alpha = 0.14f), modifier = modifier) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = tint, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 3.dp))
    }
}

/** Thin progress capsule (basket / open) under a shop header. */
@Composable
fun ProgressCapsule(value: Float, tint: Color, modifier: Modifier = Modifier) {
    LinearProgressIndicator(
        progress = { value }, color = tint, trackColor = tint.copy(alpha = 0.15f), gapSize = 0.dp, drawStopIndicator = {},
        modifier = modifier.fillMaxWidth().height(4.dp),
    )
}

/** Friendly empty state with a gradient tile. */
@Composable
fun EmptyState(icon: ImageVector, title: String, text: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(96.dp).background(Brush.linearGradient(listOf(Brand.Primary, Brand.PrimaryDeep)), RoundedCornerShape(28.dp)),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp)) }
        Text(title, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 16.dp, bottom = 6.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

/**
 * Soft brand glow behind a large title that fades into the ground
 * (design canvas: 26 % → 6 % at 60 % → 0 over the top 320 dp; a shop's own colour at 42 %).
 */
@Composable
fun HeroGlow(tint: Color = Brand.Primary, strength: Float = 0.26f, modifier: Modifier = Modifier) {
    val top = if (isSystemInDarkTheme()) strength * 1.4f else strength
    Box(
        modifier.fillMaxWidth().height(320.dp).background(
            Brush.verticalGradient(0f to tint.copy(alpha = top), 0.6f to tint.copy(alpha = strength * 0.23f), 1f to Color.Transparent),
        ),
    )
}

/**
 * Ground + glow for a whole screen: the Scaffold inside must be transparent (`containerColor =
 * Color.Transparent`, top bar `groundTopBarColors()`), or it paints over the glow.
 */
@Composable
fun Ground(tint: Color = Brand.Primary, strength: Float = 0.26f, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLow)) {
        HeroGlow(tint, strength)
        content()
    }
}

/**
 * The floating call to action: a flat pill with a subtle Leaf gradient (lighter top-start, deeper
 * bottom-end), a soft shadow and a press squash. No highlights or rims.
 */
@Composable
fun GradientFab(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.94f else 1f, label = "fab-press")
    val shape = RoundedCornerShape(20.dp)
    Row(
        modifier
            .scale(scale)
            .shadow(10.dp, shape, ambientColor = Brand.PrimaryDeep.copy(alpha = 0.28f), spotColor = Brand.PrimaryDeep.copy(alpha = 0.28f))
            .background(Brush.linearGradient(listOf(Brand.Primary, Brand.PrimaryDeep)), shape)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .height(56.dp)
            .padding(start = 18.dp, end = 22.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides Color.White) { content() }
    }
}

/** Top bar colours for a screen on [Ground]: see-through at rest, solid once content scrolls under it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun groundTopBarColors(): TopAppBarColors = TopAppBarDefaults.topAppBarColors(
    containerColor = Color.Transparent,
    scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainer,
)
