package com.oryjk.sumly.features.market

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.delay

@Composable
internal fun MarketPriceChart(
    state: MarketUiState,
    observations: List<MarketChartPoint>,
    zone: ZoneId,
    overlay: MarketHoldingOverlay?,
    resetRevision: Int,
    onZoomChanged: (Boolean) -> Unit,
    onSources: () -> Unit,
    onRetry: () -> Unit,
) {
    val live = state.range == MarketRange.Realtime
    var window by remember(state.basis, state.range, resetRevision) { mutableStateOf(0f..1f) }
    var selection by remember(state.basis, state.range, resetRevision) { mutableStateOf<Instant?>(null) }
    var selectedMarkerDay by remember(state.basis, state.range, resetRevision, overlay) { mutableStateOf<LocalDate?>(null) }
    var showDates by remember(state.basis, state.range) { mutableStateOf(false) }

    LaunchedEffect(selection) {
        if (selection != null) {
            delay(5_000L)
            selection = null
        }
    }
    val first = observations.firstOrNull()?.time
    val last = observations.lastOrNull()?.time
    val interval = if (live) state.realtime?.intervalSeconds ?: 5 else null
    val timing = interval?.let { RealtimeChartTiming(first, last, state.quote?.asOf, it, state.observedAt, zone) }
    val full = when {
        first == null || last == null -> null
        live -> MarketTimeBounds(minOf(first, last.minusSeconds(MarketChartLogic.REALTIME_WINDOW_SECONDS)), last)
        state.range == MarketRange.History && state.basis == MarketBasis.Domestic -> MarketTimeBounds(first, last)
        else -> state.range.dateBounds(state.observedAt.atZone(zone).toLocalDate())?.let { dates ->
            MarketTimeBounds(dates.start.atMarketNoon(zone), dates.endInclusive.atMarketNoon(zone))
        }
    }
    val viewport = full?.subrange(window)?.let {
        if (live) it else MarketTimeBounds(
            it.start.atZone(zone).toLocalDate().atMarketNoon(zone),
            it.end.atZone(zone).toLocalDate().atMarketNoon(zone),
        )
    }
    val points = remember(observations, viewport) {
        if (viewport == null) emptyList() else observations.filter { it.time in viewport.start..viewport.end }
    }
    val projection = remember(points, state.scale) { if (points.isEmpty()) null else PriceProjection.forPoints(points, state.scale) }
    val selected = selection?.let { MarketChartLogic.nearestPoint(points, it) }
    val activeOverlay = overlay?.takeIf { projection != null }
    val breakEven = activeOverlay?.breakEvenCnyPerGram
    val markers = remember(activeOverlay, viewport, observations, projection, live) {
        if (live || viewport == null || projection == null) emptyList() else activeOverlay?.purchases.orEmpty()
            .asSequence()
            .filter { projection.contains(it.costCnyPerGram) && it.count > 0 }
            .map { MarketChartLogic.resolveMarker(it, observations, zone) }
            .filter { it.time in viewport.start..viewport.end }
            .toList()
    }
    val paused = timing?.paused == true
    val dateFormat = if (live) "MM-dd HH:mm:ss" else "yyyy/MM/dd"
    val changeWindow: (ClosedFloatingPointRange<Float>) -> Unit = {
        window = it
        selection = null
        selectedMarkerDay = null
        onZoomChanged(it != 0f..1f)
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        val caption = when {
            timing != null -> timing.caption
            state.basis == MarketBasis.Domestic -> "截至昨天 · 元/克 · Au99.99"
            else -> "截至昨天 · 元/克 · 按最新汇率折算"
        }
        Row(
            Modifier.clickable(onClick = onSources),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(caption, color = if (paused) GoldColors.GoldSoft else GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
            Icon(Icons.Default.Info, contentDescription = "行情数据说明", tint = GoldColors.GoldSoft, modifier = Modifier.size(13.dp))
        }
        if (points.isNotEmpty()) {
            MarketChartSummary(points, breakEven, hasPurchases = markers.isNotEmpty())
        }
        if (selected != null) {
            val whenText = if (selected.granularity == MarketGranularity.Annual) {
                "${marketTime(selected.time, zone, "yyyy")} 年度均价参考"
            } else marketTime(selected.time, zone, dateFormat)
            Text("$whenText  ${marketMoney(selected.price)} 元/克", color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
        }
        if (points.isEmpty() || viewport == null || projection == null) {
            Box(Modifier.fillMaxWidth().height(230.dp), contentAlignment = Alignment.Center) {
                when {
                    state.chartLoading -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        Text("正在加载走势…", color = GoldColors.Muted)
                    }
                    state.chartFailed -> TextButton(onClick = onRetry) { Text("走势加载失败 · 重试") }
                    else -> Text("暂无所选区间走势", color = GoldColors.Muted)
                }
            }
        } else {
            MarketChartCanvas(
                points = points,
                viewport = viewport,
                projection = projection,
                zone = zone,
                selected = selected,
                breakEven = breakEven?.takeIf(projection::contains),
                markers = markers,
                intervalSeconds = interval,
                onInspect = { selection = it; selectedMarkerDay = null },
                onInspectMarker = { selectedMarkerDay = it.marker.date; selection = null },
                onTransform = { anchor, zoom, pan ->
                    val next = transformMarketWindow(window, anchor, zoom, pan, full.minimumFraction(live))
                    if (next != window) changeWindow(next)
                },
            )
            val dates = viewport.start..viewport.end
            val axis = (0..3).map { viewport.at(it / 3f) }.map {
                timing?.axisLabel(it, dates) ?: marketTime(it, zone, "yy/MM/dd")
            }.distinct()
            Row(Modifier.fillMaxWidth().padding(top = 3.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                axis.forEachIndexed { index, label ->
                    val alignment = when (index) {
                        0 -> TextAlign.Start
                        axis.lastIndex -> TextAlign.End
                        else -> TextAlign.Center
                    }
                    Text(label, color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall, textAlign = alignment)
                }
            }
        }
        if (full != null && viewport != null) {
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Row(
                    modifier = if (live) Modifier else Modifier.clickable { showDates = true },
                    horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (!live) Icon(Icons.Default.CalendarMonth, contentDescription = null, tint = GoldColors.GoldSoft, modifier = Modifier.size(15.dp))
                    val label = timing?.windowLabel(viewport.start..viewport.end)
                        ?: "${marketTime(viewport.start, zone, dateFormat)} — ${marketTime(viewport.end, zone, dateFormat)}"
                    Text(label,
                        color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                    if (!live) Icon(Icons.Default.KeyboardArrowDown, contentDescription = "选择日期范围", tint = GoldColors.GoldSoft, modifier = Modifier.size(15.dp))
                }
                Text("${points.size} 个点", color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
            }
            if (full.start < full.end) {
                MarketChartNavigator(observations, full, state.scale, window, full.minimumFraction(live), interval, changeWindow)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    val dates = full.start..full.end
                    for (boundary in listOf(full.start, full.end)) {
                        val label = timing?.boundaryLabel(boundary, dates) ?: marketTime(boundary, zone, dateFormat)
                        Text(label, color = GoldColors.Faint, style = MaterialTheme.typography.labelSmall)
                    }
                }
                Text("单指查价 · 双指缩放或移动 · 下方选择区间", modifier = Modifier.align(Alignment.CenterHorizontally),
                    color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
            }
            if (showDates && !live) {
                MarketRangeDateDialog(full, viewport, zone, onDismiss = { showDates = false }) { from, to ->
                    showDates = false
                    changeWindow(full.fraction(from.atMarketNoon(zone))..full.fraction(to.atMarketNoon(zone)))
                }
            }
        }
        if (state.chartFailed && observations.isNotEmpty()) {
            TextButton(onClick = onRetry) { Text("走势刷新失败 · 显示上次结果") }
        }
    }
    markers.firstOrNull { it.marker.date == selectedMarkerDay }?.let {
        MarketPurchaseMarkerSheet(it, state.basis, zone, onDismiss = { selectedMarkerDay = null })
    }
}

internal fun transformMarketWindow(
    window: ClosedFloatingPointRange<Float>,
    anchor: Float,
    zoom: Float,
    pan: Float,
    minWidth: Float,
): ClosedFloatingPointRange<Float> {
    if (!anchor.isFinite() || !zoom.isFinite() || zoom <= 0f || !pan.isFinite()) return window
    val center = anchor.coerceIn(0f, 1f)
    val width = window.endInclusive - window.start
    val nextWidth = (width / zoom).coerceIn(minWidth, 1f)
    val left = (window.start + width * center - nextWidth * (center + pan)).coerceIn(0f, 1f - nextWidth)
    return left..(left + nextWidth)
}

@Composable
private fun MarketChartSummary(points: List<MarketChartPoint>, breakEven: Double?, hasPurchases: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (points.size > 1) {
            val change = points.last().price - points.first().price
            val percent = change / points.first().price * 100
            Text("区间 ${marketSigned(change)} 元/克 (${marketSigned(percent)}%)", color = marketDirection(change),
                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
        }
        breakEven?.let {
            Text("· 保本 ¥${marketMoney(it)}", color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
        }
        if (hasPurchases) {
            Box(Modifier.size(6.dp).background(GoldColors.Up, CircleShape))
            Text("买入点", color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
        }
    }
}

internal fun LocalDate.atMarketNoon(zone: ZoneId): Instant = atTime(java.time.LocalTime.NOON).atZone(zone).toInstant()

internal data class MarketTimeBounds(val start: Instant, val end: Instant) {
    private val widthMillis: Long = end.toEpochMilli() - start.toEpochMilli()

    fun at(fraction: Float): Instant = start.plusMillis((widthMillis * fraction.toDouble().coerceIn(0.0, 1.0)).toLong())
    fun fraction(time: Instant): Float = if (widthMillis == 0L) 0.5f else ((time.toEpochMilli() - start.toEpochMilli()).toDouble() / widthMillis).toFloat()
    fun subrange(window: ClosedFloatingPointRange<Float>) = MarketTimeBounds(at(window.start), at(window.endInclusive))
    fun minimumFraction(live: Boolean): Float = if (widthMillis == 0L) 1f else {
        (if (live) 30_000f else 86_400_000f).div(widthMillis).coerceAtMost(1f)
    }
}

internal class PriceProjection(private val scale: ChartScale, private val low: Double, private val high: Double) {
    fun fraction(price: Double): Float = ((high - scale.value(price)) / (high - low)).toFloat()
    fun contains(price: Double): Boolean = price.isFinite() && price > 0 && scale.value(price) in low..high

    companion object {
        fun forPoints(points: List<MarketChartPoint>, scale: ChartScale): PriceProjection {
            val low = points.minOf { scale.value(it.price) }
            val high = points.maxOf { scale.value(it.price) }
            val minimum = if (scale == ChartScale.Logarithmic) 0.01 else 0.5
            val padding = maxOf((high - low) * 0.16, minimum)
            return PriceProjection(scale, low - padding, high + padding)
        }
    }
}
