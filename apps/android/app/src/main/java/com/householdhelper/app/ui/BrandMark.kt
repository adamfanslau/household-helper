package com.householdhelper.app.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.householdhelper.app.ui.theme.Brand
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * The Orbit mark: a roof that turns into a tick (one ribbon) with a spark orbiting the house.
 * Same 120 × 120 geometry as iOS BrandMark.swift, the launcher icon and the design canvas.
 */
object BrandMarkGeometry {
    const val SIZE = 120f
    val roof = listOf(22f to 70f, 60f to 34f, 98f to 70f)
    val tick = listOf(34f to 76f, 52f to 94f, 92f to 54f)
    val orbitCenter = Offset(60f, 64f)
    val orbitRadii = Size(54f, 22f)
    const val ORBIT_DEG = -18f

    /** Spark centre at parameter t ∈ [0, 1) along the orbit; t = 0 is the resting position (109,47). */
    fun orbitPoint(t: Float, rect: Rect): Offset {
        val a = t * 2 * PI
        val x = orbitRadii.width * cos(a).toFloat(); val y = orbitRadii.height * sin(a).toFloat()
        val rad = ORBIT_DEG * PI / 180
        val px = orbitCenter.x + x * cos(rad).toFloat() - y * sin(rad).toFloat()
        val py = orbitCenter.y + x * sin(rad).toFloat() + y * cos(rad).toFloat()
        return Offset(rect.left + px / SIZE * rect.width, rect.top + py / SIZE * rect.height)
    }

    fun polyline(points: List<Pair<Float, Float>>, rect: Rect): Path = Path().apply {
        points.forEachIndexed { i, (x, y) ->
            val px = rect.left + x / SIZE * rect.width; val py = rect.top + y / SIZE * rect.height
            if (i == 0) moveTo(px, py) else lineTo(px, py)
        }
    }

    fun spark(center: Offset, outer: Float, inner: Float): Path = Path().apply {
        for (i in 0 until 8) {
            val a = i * PI / 4 - PI / 2
            val r = if (i % 2 == 0) outer else inner
            val p = Offset(center.x + r * cos(a).toFloat(), center.y + r * sin(a).toFloat())
            if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
        }
        close()
    }
}

private val Mint = Color(0xFF6FD9A6)
private val Tile = Color(0xFF10201A)

/**
 * The mark on a dark tile (sign-in hero) or bare (loading). `spinning` sends the spark around the
 * orbit once every 1.6 s with its trail.
 */
@Composable
fun BrandMark(size: Dp, modifier: Modifier = Modifier, darkTile: Boolean = true, spinning: Boolean = false) {
    val t: Float = if (spinning) {
        val transition = rememberInfiniteTransition(label = "orbit")
        val v by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = LinearEasing), RepeatMode.Restart), label = "spark")
        v
    } else 0f
    Canvas(modifier.size(size).clearAndSetSemantics { }) {
        val full = Rect(Offset.Zero, this.size)
        if (darkTile) drawRoundRect(Tile, cornerRadius = CornerRadius(this.size.width * 0.27f))
        val rect = if (darkTile) full.deflate(this.size.width * 0.08f) else full
        drawMark(rect, t)
    }
}

/** The spark alone: the "smart" glyph for suggestions and assistant hints. */
@Composable
fun SparkGlyph(size: Dp = 18.dp, tint: Color = Brand.Primary, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size).clearAndSetSemantics { }) {
        val w = this.size.width
        drawPath(BrandMarkGeometry.spark(Offset(w / 2, w / 2), w / 2, w / 6), tint)
        drawPath(BrandMarkGeometry.spark(Offset(w * 0.86f, w * 0.18f), w * 0.14f, w * 0.05f), tint.copy(alpha = 0.7f))
    }
}

private fun DrawScope.drawMark(rect: Rect, t: Float) {
    val s = rect.width / BrandMarkGeometry.SIZE
    val stroke = Stroke(width = 12f * s, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val cx = rect.left + BrandMarkGeometry.orbitCenter.x * s; val cy = rect.top + BrandMarkGeometry.orbitCenter.y * s
    rotate(BrandMarkGeometry.ORBIT_DEG, Offset(cx, cy)) {
        drawOval(
            Mint.copy(alpha = 0.42f),
            topLeft = Offset(cx - BrandMarkGeometry.orbitRadii.width * s, cy - BrandMarkGeometry.orbitRadii.height * s),
            size = Size(BrandMarkGeometry.orbitRadii.width * 2 * s, BrandMarkGeometry.orbitRadii.height * 2 * s),
            style = Stroke(3.5f * s),
        )
    }
    drawPath(BrandMarkGeometry.polyline(BrandMarkGeometry.roof, rect), Brush.linearGradient(listOf(Mint, Brand.Primary), rect.topLeft, rect.bottomRight), style = stroke)
    drawPath(BrandMarkGeometry.polyline(BrandMarkGeometry.tick, rect), Color.White, style = stroke)
    for ((lag, radius, alpha) in listOf(Triple(0.06f, 1.8f, 0.4f), Triple(0.03f, 2.5f, 0.7f))) {
        drawCircle(Mint.copy(alpha = alpha), radius * s, BrandMarkGeometry.orbitPoint(t - lag, rect))
    }
    drawPath(BrandMarkGeometry.spark(BrandMarkGeometry.orbitPoint(t, rect), 8.5f * s, 2.8f * s), Mint)
}
