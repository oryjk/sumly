package com.oryjk.sumly.features.market

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MarketChartLogicTest {
    @Test
    fun `two finger zoom anchors to the touched date and clamps the viewport`() {
        val zoomed = transformMarketWindow(0f..1f, anchor = 0.25f, zoom = 2f, pan = 0f, minWidth = 0.1f)
        assertEquals(0.125f, zoomed.start, 0.0001f)
        assertEquals(0.625f, zoomed.endInclusive, 0.0001f)
        val moved = transformMarketWindow(zoomed, anchor = 0.5f, zoom = 1f, pan = 0.5f, minWidth = 0.1f)
        assertEquals(0f, moved.start, 0.0001f)
        assertEquals(0.5f, moved.endInclusive, 0.0001f)
        val narrow = transformMarketWindow(zoomed, anchor = 0.5f, zoom = 100f, pan = 0f, minWidth = 0.1f)
        assertEquals(0.1f, narrow.endInclusive - narrow.start, 0.0001f)
    }

    @Test
    fun `London history uses latest conversion and excludes today`() {
        val now = instant("2026-11-20T16:30:00Z")
        val points = MarketChartLogic.historicalPoints(
            observations = listOf(observation("2026-11-21", 2_100.0), observation("2026-11-20", 2_000.0)),
            basis = MarketBasis.International,
            range = MarketRange.Month,
            usdCny = 7.0,
            now = now,
            zone = ZoneOffset.ofHours(8),
        )

        assertEquals(1, points.size)
        assertEquals(instant("2026-11-20T04:00:00Z"), points.single().time)
        assertEquals(2_000.0 * 7.0 / 31.1034768, points.single().price, 0.00001)
    }

    @Test
    fun `London history remains empty until a real exchange rate is available`() {
        val points = MarketChartLogic.historicalPoints(
            observations = listOf(observation("2026-11-20", 2_000.0)),
            basis = MarketBasis.International,
            range = MarketRange.Month,
            usdCny = null,
            now = instant("2026-11-21T00:00:00Z"),
            zone = ZoneOffset.UTC,
        )

        assertTrue(points.isEmpty())
    }

    @Test
    fun `real time pause keeps the last actual twenty minute window`() {
        val now = instant("2026-11-21T00:00:00Z")
        val window = RealtimeWindow(
            intervalSeconds = 60,
            points = listOf(
                chartPoint("2026-11-19T00:20:00Z", 900.0),
                chartPoint("2026-11-19T00:00:00Z", 895.0),
                chartPoint("2026-11-18T23:59:59Z", 899.0),
                chartPoint("2026-11-21T01:00:00Z", 910.0),
            ),
        )

        val points = MarketChartLogic.realtimePoints(window, now)

        assertEquals(listOf(895.0, 900.0), points.map { it.price })
        assertTrue(MarketChartLogic.isPaused(points.last().time, null, window.intervalSeconds, now))
    }

    @Test
    fun `real time tolerates the backend minute fallback without synthesizing samples`() {
        val now = instant("2026-11-21T00:00:00Z")
        assertFalse(MarketChartLogic.isPaused(now.minusSeconds(90), now.minusSeconds(15), 60, now))
        assertTrue(MarketChartLogic.isPaused(now.minusSeconds(90), now.minusSeconds(15), 5, now))
    }

    @Test
    fun `real time keeps the latest full session and leaves a break at lunch`() {
        val earlier = chartPoint("2026-11-20T18:00:00Z", 886.0)
        val morning = chartPoint("2026-11-21T01:00:00Z", 900.0)
        val beforeLunch = chartPoint("2026-11-21T03:30:00Z", 895.0)
        val afterLunch = chartPoint("2026-11-21T05:30:00Z", 905.0)
        val latest = chartPoint("2026-11-21T05:31:00Z", 906.0)
        val points = MarketChartLogic.realtimePoints(
            RealtimeWindow(60, listOf(earlier, morning, beforeLunch, afterLunch, latest), 86_400),
            latest.time,
        )

        assertEquals(listOf(morning, beforeLunch, afterLunch, latest), points)
        assertEquals(listOf(listOf(beforeLunch), listOf(afterLunch, latest)),
            MarketChartLogic.chartSegments(points.drop(1), intervalSeconds = 60))
    }

    @Test
    fun `overlapping legacy windows extend the session without duplicating the shared timestamp`() {
        val now = instant("2026-11-21T00:51:00Z")
        val first = chartPoint("2026-11-21T00:20:00Z", 902.0)
        val previous = chartPoint("2026-11-21T00:35:00Z", 905.0)
        val updated = previous.copy(price = 906.0)
        val latest = chartPoint("2026-11-21T00:50:00Z", 911.0)
        val merged = MarketChartLogic.mergeRealtime(
            RealtimeWindow(60, listOf(first, previous)),
            RealtimeWindow(60, listOf(updated, latest)),
            now,
        )

        assertEquals(listOf(first, updated, latest), merged?.points)
    }

    @Test
    fun `cross-midnight session labels distinguish dates and paused session from rolling window`() {
        val previous = instant("2026-11-20T22:00:00Z")
        val latest = instant("2026-11-21T01:00:00Z")
        val timing = RealtimeChartTiming(previous, latest, null, 60, latest.plusSeconds(250), ZoneOffset.UTC)

        assertEquals("休市停盘 · 最近交易时段分时", timing.caption)
        assertEquals("11/20\n22:00", timing.axisLabel(previous, previous..latest))
        assertEquals("11/21 01:00", timing.boundaryLabel(latest, previous..latest))
        assertEquals("11/20 22:00 — 11/21 01:00", timing.windowLabel(previous..latest))
    }

    @Test
    fun `scrubbing chooses the earlier observation at equal distance`() {
        val points = listOf(
            chartPoint("2026-11-20T00:00:00Z", 800.0),
            chartPoint("2026-11-20T00:02:00Z", 810.0),
        )

        assertEquals(points.first(), MarketChartLogic.nearestPoint(points, instant("2026-11-20T00:01:00Z")))
    }

    @Test
    fun `purchase marker uses its actual date and interpolates only the market anchor across holidays`() {
        val marker = MarketPurchaseMarker(LocalDate.parse("2026-11-21"), 930.0)
        val curve = listOf(
            chartPoint("2026-11-20T12:00:00Z", 890.0),
            chartPoint("2026-11-23T12:00:00Z", 920.0),
        )

        val resolved = MarketChartLogic.resolveMarker(marker, curve, ZoneOffset.UTC)

        assertEquals(instant("2026-11-21T12:00:00Z"), resolved.time)
        assertEquals(930.0, resolved.marker.costCnyPerGram, 0.0001)
        assertEquals(900.0, resolved.anchorPrice!!, 0.0001)
        assertTrue(resolved.interpolated)
        assertEquals(2, curve.size)
    }

    @Test
    fun `sync delta replaces a point and removes a tombstone in the same snapshot`() {
        val first = observation("2026-11-18", 900.0)
        val second = observation("2026-11-19", 905.0)
        val snapshot = HistorySyncPage("au9999", "CNY/g", "one", true, listOf(first, second))
            .merge(MarketBasis.Domestic, null)
        val update = HistorySyncPage("au9999", "CNY/g", "two", false, listOf(
            first.copy(deleted = true),
            second.copy(close = 908.0),
        ))

        val current = update.merge(MarketBasis.Domestic, snapshot)

        assertEquals("two", current.cursor)
        assertEquals(listOf(second.copy(close = 908.0)), current.observations)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `sync rejects a delta when its base snapshot is missing`() {
        HistorySyncPage("au9999", "CNY/g", "cursor", false, emptyList())
            .merge(MarketBasis.Domestic, null)
    }

    private fun instant(raw: String): Instant = Instant.parse(raw)

    private fun chartPoint(raw: String, price: Double) = MarketChartPoint(instant(raw), price)

    private fun observation(raw: String, price: Double) = MarketObservation(
        date = LocalDate.parse(raw),
        granularity = MarketGranularity.Daily,
        open = price,
        high = price,
        low = price,
        close = price,
        source = "test",
    )
}
