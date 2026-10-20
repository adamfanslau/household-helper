package com.householdhelper.app.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
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

/** Soft brand glow behind a large title that fades into the surface. */
@Composable
fun HeroGlow(tint: Color = Brand.Primary, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(320.dp).background(Brush.verticalGradient(listOf(tint.copy(alpha = 0.22f), tint.copy(alpha = 0.06f), Color.Transparent))))
}
