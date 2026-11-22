package com.oryjk.sumly.features.market

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

internal class RealtimeChartTiming(
    first: Instant?,
    last: Instant?,
    quote: Instant?,
    intervalSeconds: Int,
    private val now: Instant,
    private val zone: ZoneId,
) {
    val paused = last != null && MarketChartLogic.isPaused(last, quote, intervalSeconds, now)
    val caption: String = when {
        first == null || last == null -> "暂无实时走势"
        isSession(first..last) && paused -> "休市停盘 · 最近交易时段分时"
        isSession(first..last) -> "实时更新 · 本交易时段分时"
        paused -> "更新暂停 · 最近可用 20 分钟"
        else -> "最近 20 分钟"
    }

    fun windowLabel(window: ClosedRange<Instant>): String {
        val session = isSession(window)
        val day = if (session) "MM/dd" else "yyyy.MM.dd"
        val time = if (session) "HH:mm" else "HH:mm:ss"
        val start = window.start
        val end = window.endInclusive
        return when {
            !sameDay(start, end) -> "${format(start, "$day $time")} — ${format(end, "$day $time")}"
            !sameDay(end, now) -> "${format(start, "$day $time")} — ${format(end, time)}"
            else -> "${format(start, time)} — ${format(end, time)}"
        }
    }

    fun axisLabel(time: Instant, window: ClosedRange<Instant>): String = label(time, window, "\n")
    fun boundaryLabel(time: Instant, window: ClosedRange<Instant>): String = label(time, window, " ")

    private fun label(time: Instant, window: ClosedRange<Instant>, separator: String): String {
        val clock = format(time, "HH:mm")
        if (sameDay(time, now) && sameDay(window.start, window.endInclusive)) return clock
        val day = format(time, if (isSession(window)) "MM/dd" else "MM.dd")
        return "$day$separator$clock"
    }

    private fun sameDay(a: Instant, b: Instant): Boolean = a.atZone(zone).toLocalDate() == b.atZone(zone).toLocalDate()
    private fun isSession(window: ClosedRange<Instant>): Boolean =
        Duration.between(window.start, window.endInclusive) > Duration.ofMinutes(30)

    private fun format(time: Instant, pattern: String): String =
        DateTimeFormatter.ofPattern(pattern, Locale.ROOT).withZone(zone).format(time)
}
