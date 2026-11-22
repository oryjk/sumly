package com.oryjk.sumly.features.macro

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToLong

internal data class MacroChartSeries(val label: String, val points: List<MacroPoint>, val color: Color)

@Composable
internal fun MacroRanges(selected: MacroRange, temperature: Boolean = false, onSelect: (MacroRange) -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        MacroRange.entries.filter { !temperature || it != MacroRange.TenYears }.forEach { range ->
            FilterChip(selected = range == selected, onClick = { onSelect(range) }, label = { Text(range.title) })
        }
    }
}

@Composable
internal fun MacroHistoryChart(
    title: String,
    series: List<MacroChartSeries>,
    unit: String,
    fixedRange: ClosedFloatingPointRange<Double>? = null,
) {
    val active = remember(series) { series.filter { it.points.isNotEmpty() } }
    Text(title, style = MaterialTheme.typography.titleSmall, color = GoldColors.GoldSoft)
    if (active.isEmpty()) {
        Text("当前区间暂无历史观测", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
        return
    }
    val points = remember(active) { active.flatMap { it.points } }
    val dates = remember(points) { points.map { it.date.toEpochDay() }.distinct().sorted() }
    val firstDay = dates.first()
    val lastDay = dates.last()
    val supportsLog = remember(points, dates, fixedRange) {
        fixedRange == null && dates.size >= 2 && points.all { it.value > 0 && it.value.isFinite() }
    }
    var preferLog by rememberSaveable(title, supportsLog) { mutableStateOf(false) }
    val logScale = preferLog && supportsLog
    fun project(value: Double): Double = if (logScale) log10(value) else value
    fun sourceValue(value: Double): Double = if (logScale) 10.0.pow(value) else value
    if (supportsLog) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !logScale, onClick = { preferLog = false }, label = { Text("线性") })
            FilterChip(selected = logScale, onClick = { preferLog = true }, label = { Text("对数") })
        }
    }
    val low = remember(points, fixedRange, logScale) { fixedRange?.start ?: points.minOf { project(it.value) } }
    val high = remember(points, fixedRange, logScale) { fixedRange?.endInclusive ?: points.maxOf { project(it.value) } }
    val padding = if (high == low) abs(low * 0.05).coerceAtLeast(0.5) else (high - low) * 0.08
    val yMin = if (fixedRange == null) low - padding else low
    val yMax = if (fixedRange == null) high + padding else high
    var selectedDay by remember(dates) { mutableStateOf<Long?>(null) }
    val chooseDay = { x: Float, width: Int ->
        val ratio = (x / width.coerceAtLeast(1)).coerceIn(0f, 1f).toDouble()
        val targetDay = firstDay + ((lastDay - firstDay) * ratio).roundToLong()
        val index = dates.binarySearch(targetDay)
        selectedDay = if (index >= 0) dates[index] else {
            val insertion = -index - 1
            val previous = dates[(insertion - 1).coerceAtLeast(0)]
            val next = dates[insertion.coerceAtMost(dates.lastIndex)]
            if (targetDay - previous <= next - targetDay) previous else next
        }
    }
    val selected = selectedDay?.let { day ->
        val date = LocalDate.ofEpochDay(day)
        active.mapNotNull { trace ->
            val index = trace.points.binarySearchBy(date, selector = MacroPoint::date)
            trace.points.getOrNull(index)?.let { trace to it }
        }
    }.orEmpty()
    val date = selectedDay?.let(LocalDate::ofEpochDay)
    if (date != null) {
        Text(date.toString(), style = MaterialTheme.typography.labelSmall, color = GoldColors.Muted)
    }
    if (series.size > 1 || selected.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            active.forEach { trace ->
                val value = selected.firstOrNull { it.first == trace }?.second
                Text(
                    if (value != null) "${trace.label} ${value.value.formatted(2, unit)}" else trace.label,
                    style = MaterialTheme.typography.labelSmall,
                    color = trace.color,
                )
            }
        }
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Canvas(
            Modifier.weight(1f).height(150.dp)
                .pointerInput(dates) { detectTapGestures { chooseDay(it.x, size.width) } }
                .pointerInput(dates) {
                    detectHorizontalDragGestures { change, _ -> chooseDay(change.position.x, size.width) }
                },
        ) {
            val inset = 4.dp.toPx()
            val right = size.width - inset
            val bottom = size.height - inset
            val width = (right - inset).coerceAtLeast(1f)
            val height = (bottom - inset).coerceAtLeast(1f)

            fun x(day: Long): Float = if (firstDay == lastDay) size.width / 2 else {
                inset + ((day - firstDay).toDouble() / (lastDay - firstDay) * width).toFloat()
            }

            fun y(value: Double): Float = bottom - ((project(value) - yMin) / (yMax - yMin) * height).toFloat()

            repeat(4) { index ->
                val horizontal = inset + height * index / 3
                drawLine(GoldColors.Border, Offset(inset, horizontal), Offset(right, horizontal), 1.dp.toPx())
            }
            active.forEach { trace ->
                if (trace.points.size == 1) {
                    val point = trace.points.single()
                    drawCircle(trace.color, 3.dp.toPx(), Offset(x(point.date.toEpochDay()), y(point.value)))
                } else {
                    val path = Path()
                    val first = trace.points.first()
                    path.moveTo(x(first.date.toEpochDay()), y(first.value))
                    trace.points.forEachIndexed { index, point ->
                        if (index > 0) path.lineTo(x(point.date.toEpochDay()), y(point.value))
                    }
                    drawPath(path, trace.color, style = Stroke(width = 1.8.dp.toPx()))
                }
            }
            selectedDay?.let { day ->
                val pointerX = x(day)
                drawLine(GoldColors.GoldSoft, Offset(pointerX, inset), Offset(pointerX, bottom))
            }
            selected.forEach { (trace, point) ->
                drawCircle(trace.color, 3.dp.toPx(), Offset(x(point.date.toEpochDay()), y(point.value)))
            }
        }
        Column(Modifier.height(150.dp).padding(start = 4.dp), verticalArrangement = Arrangement.SpaceBetween) {
            (0..3).forEach { index ->
                Text(
                    sourceValue(yMax - (yMax - yMin) * index / 3).formatted(1),
                    color = GoldColors.Muted,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(LocalDate.ofEpochDay(firstDay).toString(), style = MaterialTheme.typography.labelSmall, color = GoldColors.Muted)
        if (lastDay != firstDay) {
            Text(LocalDate.ofEpochDay(lastDay).toString(), style = MaterialTheme.typography.labelSmall, color = GoldColors.Muted)
        }
    }
}
