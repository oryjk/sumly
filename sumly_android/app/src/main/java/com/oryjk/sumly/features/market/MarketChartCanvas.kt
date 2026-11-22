package com.oryjk.sumly.features.market

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import java.time.Instant
import java.time.ZoneId
import kotlin.math.hypot

private const val CHART_TOP_PADDING = 0.095f
private const val CHART_INNER_HEIGHT = 0.81f

@Composable
internal fun MarketChartCanvas(
    points: List<MarketChartPoint>,
    viewport: MarketTimeBounds,
    projection: PriceProjection,
    zone: ZoneId,
    selected: MarketChartPoint?,
    breakEven: Double?,
    markers: List<ResolvedPurchaseMarker>,
    intervalSeconds: Int?,
    onInspect: (Instant) -> Unit,
    onInspectMarker: (ResolvedPurchaseMarker) -> Unit,
    onTransform: (anchor: Float, zoom: Float, pan: Float) -> Unit,
) {
    val inspect = rememberUpdatedState(onInspect)
    val inspectMarker = rememberUpdatedState(onInspectMarker)
    val transform = rememberUpdatedState(onTransform)
    val high = remember(points) { points.maxBy { it.price } }
    val low = remember(points) { points.minBy { it.price } }
    val segments = remember(points, intervalSeconds) { MarketChartLogic.chartSegments(points, intervalSeconds) }
    fun verticalPosition(price: Double) = CHART_TOP_PADDING + projection.fraction(price) * CHART_INNER_HEIGHT
    BoxWithConstraints(Modifier.fillMaxWidth().height(235.dp)) {
        Canvas(
            modifier = Modifier.matchParentSize()
                .semantics { contentDescription = "黄金走势图，当前区间 ${points.size} 个行情点" }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        var transforming = false
                        do {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            if (event.changes.count { it.pressed } >= 2) {
                                transforming = true
                                if (event.changes.count { it.pressed && it.previousPressed } >= 2) {
                                    val width = size.width.coerceAtLeast(1)
                                    transform.value(
                                        event.calculateCentroid(useCurrent = false).x / width,
                                        event.calculateZoom(),
                                        event.calculatePan().x / width,
                                    )
                                }
                            }
                            if (transforming) event.changes.forEach { it.consume() }
                        } while (event.changes.any { it.pressed })
                    }
                }
                .pointerInput(viewport, markers, projection) {
                    detectTapGestures { position ->
                        val hit = markers.minByOrNull { marker ->
                            hypot(viewport.fraction(marker.time) * size.width - position.x,
                                verticalPosition(marker.marker.costCnyPerGram) * size.height - position.y)
                        }
                        if (hit != null && hypot(viewport.fraction(hit.time) * size.width - position.x,
                                verticalPosition(hit.marker.costCnyPerGram) * size.height - position.y) <= 22.dp.toPx()) {
                            inspectMarker.value(hit)
                        } else {
                            inspect.value(viewport.at(position.x / size.width.coerceAtLeast(1)))
                        }
                    }
                }
                .pointerInput(viewport) {
                    detectHorizontalDragGestures(
                        onDragStart = { inspect.value(viewport.at(it.x / size.width.coerceAtLeast(1))) },
                    ) { change, _ ->
                        change.consume()
                        inspect.value(viewport.at(change.position.x / size.width.coerceAtLeast(1)))
                    }
                },
        ) {
            fun position(time: Instant, price: Double): Offset =
                Offset(viewport.fraction(time) * size.width, verticalPosition(price) * size.height)
            val brush = Brush.verticalGradient(listOf(GoldColors.Gold.copy(alpha = 0.18f), GoldColors.Gold.copy(alpha = 0f)))
            val stroke = Stroke(width = 1.8.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
            for (segment in segments) {
                val curve = segment.map { position(it.time, it.price) }
                if (curve.size == 1) {
                    drawCircle(GoldColors.Gold, radius = 3.dp.toPx(), center = curve.first())
                    continue
                }
                val line = Path().apply { moveTo(curve.first().x, curve.first().y); smoothCurve(curve) }
                val area = Path().apply {
                    moveTo(curve.first().x, size.height)
                    lineTo(curve.first().x, curve.first().y)
                    smoothCurve(curve)
                    lineTo(curve.last().x, size.height)
                    close()
                }
                drawPath(area, brush)
                drawPath(line, GoldColors.Gold, style = stroke)
            }
            if (breakEven != null) {
                val y = verticalPosition(breakEven) * size.height
                drawLine(GoldColors.GoldSoft.copy(alpha = 0.75f), Offset(0f, y), Offset(size.width, y),
                    strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            }
            for (item in markers) {
                val marker = position(item.time, item.marker.costCnyPerGram)
                item.anchorPrice?.takeIf(projection::contains)?.let { reference ->
                    val anchor = position(item.time, reference)
                    drawLine(GoldColors.Up.copy(alpha = 0.45f), marker, anchor, strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.5.dp.toPx(), 2.5.dp.toPx())))
                    drawCircle(GoldColors.Up.copy(alpha = 0.65f), radius = 2.dp.toPx(), center = anchor)
                }
                drawCircle(GoldColors.Up, radius = 4.dp.toPx(), center = marker)
            }
            drawCircle(GoldColors.GoldSoft, radius = 2.5.dp.toPx(), center = position(high.time, high.price))
            if (low.price != high.price) drawCircle(GoldColors.GoldSoft, radius = 2.5.dp.toPx(), center = position(low.time, low.price))
            selected?.let { point ->
                val marker = position(point.time, point.price)
                drawLine(GoldColors.GoldSoft.copy(alpha = 0.45f), Offset(marker.x, 0f), Offset(marker.x, size.height))
                drawCircle(GoldColors.GoldSoft, radius = 4.dp.toPx(), center = marker)
            }
        }
        val labelWidth = minOf(125.dp, maxWidth)
        val edge = maxWidth - labelWidth
        if (selected == null) {
            ChartExtremumLabel(
                "最高", high, zone, Modifier.width(labelWidth).offset(
                    x = (maxWidth * viewport.fraction(high.time) - labelWidth / 2).coerceIn(0.dp, edge),
                    y = (maxHeight * verticalPosition(high.price) - 38.dp).coerceAtLeast(0.dp),
                ),
            )
            if (low.price != high.price) {
                ChartExtremumLabel(
                    "最低", low, zone, Modifier.width(labelWidth).offset(
                        x = (maxWidth * viewport.fraction(low.time) - labelWidth / 2).coerceIn(0.dp, edge),
                        y = (maxHeight * verticalPosition(low.price) + 5.dp).coerceAtMost(maxHeight - 40.dp),
                    ),
                )
            }
        }
        breakEven?.let { base ->
            Text(
                text = "保本 ¥${marketMoney(base)}",
                modifier = Modifier.offset(y = (maxHeight * verticalPosition(base) - 21.dp).coerceAtLeast(0.dp))
                    .background(GoldColors.GoldSoft, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp),
                color = GoldColors.OnGold, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.labelSmall,
            )
        }
        for (item in markers.filter { it.marker.count > 1 }.take(24)) {
            Text(
                item.marker.count.toString(),
                modifier = Modifier.offset(
                    x = (maxWidth * viewport.fraction(item.time) + 6.dp).coerceIn(0.dp, (maxWidth - 20.dp).coerceAtLeast(0.dp)),
                    y = (maxHeight * verticalPosition(item.marker.costCnyPerGram) - 8.dp).coerceAtLeast(0.dp),
                ).background(GoldColors.SurfaceElevated, RoundedCornerShape(8.dp)).padding(horizontal = 4.dp),
                color = GoldColors.Up, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

private fun Path.smoothCurve(curve: List<Offset>) {
    for (index in 1 until curve.size) {
        val previous = curve[index - 1]
        val current = curve[index]
        val x = (previous.x + current.x) / 2f
        cubicTo(x, previous.y, x, current.y, current.x, current.y)
    }
}

@Composable
private fun ChartExtremumLabel(label: String, point: MarketChartPoint, zone: ZoneId, modifier: Modifier) {
    val time = when (point.granularity) {
        MarketGranularity.Annual -> "${marketTime(point.time, zone, "yyyy")} · 年度均价"
        MarketGranularity.Daily -> "${marketTime(point.time, zone, "yyyy/MM/dd")} · 收盘"
        MarketGranularity.Realtime -> marketTime(point.time, zone, "MM/dd HH:mm:ss")
    }
    Column(
        modifier = modifier.background(GoldColors.Surface.copy(alpha = 0.95f), RoundedCornerShape(6.dp))
            .padding(horizontal = 5.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text("$label ¥${marketMoney(point.price)}", color = GoldColors.GoldSoft,
            style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        Text(time, color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
    }
}
