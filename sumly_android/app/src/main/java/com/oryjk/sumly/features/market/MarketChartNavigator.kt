package com.oryjk.sumly.features.market

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import kotlin.math.abs

private enum class NavigatorDragPart { Start, Window, End }

@Composable
internal fun MarketChartNavigator(
    points: List<MarketChartPoint>,
    full: MarketTimeBounds,
    scale: ChartScale,
    window: ClosedFloatingPointRange<Float>,
    minimum: Float,
    intervalSeconds: Int?,
    onWindowChanged: (ClosedFloatingPointRange<Float>) -> Unit,
) {
    val current = rememberUpdatedState(window)
    val update = rememberUpdatedState(onWindowChanged)
    val projection = remember(points, scale) { PriceProjection.forPoints(points, scale) }
    val sampled = remember(points, intervalSeconds) {
        val stride = maxOf(1, points.size / 420)
        MarketChartLogic.chartSegments(points, intervalSeconds).map { segment ->
            val values = segment.indices.step(stride).map(segment::get)
            if (values.last() == segment.last()) values else values + segment.last()
        }
    }
    Canvas(
        Modifier.fillMaxWidth().padding(top = 7.dp).height(48.dp)
            .semantics {
                contentDescription = "走势图范围，拖动区间浏览，拖动两端缩放"
                customActions = listOf(
                    CustomAccessibilityAction("向左移动") { update.value(moveWindow(current.value, -0.1f)); true },
                    CustomAccessibilityAction("向右移动") { update.value(moveWindow(current.value, 0.1f)); true },
                    CustomAccessibilityAction("缩小区间") { update.value(scaleWindow(current.value, 0.75f, minimum)); true },
                    CustomAccessibilityAction("扩大区间") { update.value(scaleWindow(current.value, 1.25f, minimum)); true },
                )
            }
            .pointerInput(minimum) {
                var origin = current.value
                var part: NavigatorDragPart? = null
                var dragged = 0f
                detectHorizontalDragGestures(
                    onDragStart = { start ->
                        origin = current.value
                        dragged = 0f
                        val left = origin.start * size.width
                        val right = origin.endInclusive * size.width
                        val leftDistance = abs(start.x - left)
                        val rightDistance = abs(start.x - right)
                        part = when {
                            minOf(leftDistance, rightDistance) <= 16.dp.toPx() ->
                                if (leftDistance <= rightDistance) NavigatorDragPart.Start else NavigatorDragPart.End
                            start.x in left..right -> NavigatorDragPart.Window
                            else -> null
                        }
                    },
                    onDragEnd = { part = null },
                    onDragCancel = { part = null },
                ) { change, delta ->
                    val active = part ?: return@detectHorizontalDragGestures
                    change.consume()
                    dragged += delta / size.width.coerceAtLeast(1)
                    val next = when (active) {
                        NavigatorDragPart.Start -> (origin.start + dragged)
                            .coerceIn(0f, (origin.endInclusive - minimum).coerceAtLeast(0f))..origin.endInclusive
                        NavigatorDragPart.End -> origin.start..(origin.endInclusive + dragged)
                            .coerceIn((origin.start + minimum).coerceAtMost(1f), 1f)
                        NavigatorDragPart.Window -> moveWindow(origin, dragged)
                    }
                    update.value(next)
                }
            },
    ) {
        val corner = CornerRadius(6.dp.toPx())
        drawRoundRect(GoldColors.Surface, cornerRadius = corner)
        val sparkline = Path()
        val curveColor = GoldColors.GoldSoft.copy(alpha = 0.48f)
        for (segment in sampled) {
            for ((index, point) in segment.withIndex()) {
                val x = full.fraction(point.time) * size.width
                val y = size.height * (0.12f + projection.fraction(point.price) * 0.76f)
                when {
                    segment.size == 1 -> drawCircle(curveColor, radius = 1.dp.toPx(), center = Offset(x, y))
                    index == 0 -> sparkline.moveTo(x, y)
                    else -> sparkline.lineTo(x, y)
                }
            }
        }
        drawPath(sparkline, curveColor, style = Stroke(width = 1.dp.toPx(), cap = StrokeCap.Round))

        val left = window.start * size.width
        val right = window.endInclusive * size.width
        val thickness = 1.5.dp.toPx()
        val selectionLeft = (left + thickness / 2).coerceAtMost(size.width)
        val selectionWidth = (right - left - thickness).coerceAtLeast(0f)
        val selectionSize = Size(selectionWidth, (size.height - thickness).coerceAtLeast(0f))
        val selectionStart = Offset(selectionLeft, thickness / 2)
        drawRoundRect(GoldColors.Gold.copy(alpha = 0.15f), topLeft = selectionStart, size = selectionSize, cornerRadius = corner)
        drawRoundRect(GoldColors.Gold, topLeft = selectionStart, size = selectionSize, cornerRadius = corner, style = Stroke(thickness))
        val handleInset = minOf(8.dp.toPx(), (right - left) * 0.25f)
        for (x in listOf(left + handleInset, right - handleInset)) {
            drawLine(GoldColors.Gold, Offset(x, size.height * 0.30f), Offset(x, size.height * 0.70f),
                strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round)
        }
    }
}

private fun moveWindow(window: ClosedFloatingPointRange<Float>, delta: Float): ClosedFloatingPointRange<Float> {
    val width = window.endInclusive - window.start
    val start = (window.start + delta).coerceIn(0f, (1f - width).coerceAtLeast(0f))
    return start..(start + width).coerceAtMost(1f)
}

private fun scaleWindow(window: ClosedFloatingPointRange<Float>, scale: Float, minimum: Float): ClosedFloatingPointRange<Float> {
    val width = ((window.endInclusive - window.start) * scale).coerceIn(minimum, 1f)
    val start = ((window.start + window.endInclusive - width) / 2).coerceIn(0f, 1f - width)
    return start..(start + width).coerceAtMost(1f)
}
