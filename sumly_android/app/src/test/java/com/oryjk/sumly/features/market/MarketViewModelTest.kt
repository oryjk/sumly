package com.oryjk.sumly.features.market

import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MarketViewModelTest {
    @Test
    fun `purchase reference uses the exact daily close and converts international prices`() = runTest {
        val day = LocalDate.of(2026, 11, 20)
        val clock = Clock.fixed(Instant.parse("2026-11-21T00:00:00Z"), ZoneOffset.UTC)
        val daily = MarketObservation(day, MarketGranularity.Daily, 609.0, 650.0, 580.0, 620.0, "test")
        val service = object : GoldMarketService {
            override suspend fun cachedHistory(basis: MarketBasis) =
                listOf(daily.copy(date = day.withDayOfMonth(1), granularity = MarketGranularity.Annual), daily)
            override suspend fun fetchQuote(basis: MarketBasis): MarketQuote = error("offline")
            override suspend fun cachedQuote(basis: MarketBasis) =
                MarketQuote(2000.0, 1950.0, 450.0, 7.0, clock.instant())
            override suspend fun fetchHistory(basis: MarketBasis, force: Boolean) = cachedHistory(basis)
            override suspend fun fetchRealtime(basis: MarketBasis) = RealtimeWindow(5, emptyList())
        }
        val viewModel = MarketViewModel(service, clock)

        assertEquals(620.0, viewModel.historicalPurchasePrice(MarketBasis.Domestic, day)!!, 0.001)
        assertEquals(
            620.0 * 7.0 / 31.1034768, viewModel.historicalPurchasePrice(MarketBasis.International, day)!!, 0.001,
        )
        assertNull(viewModel.historicalPurchasePrice(MarketBasis.Domestic, day.withDayOfMonth(1)))
        assertNull(viewModel.historicalPurchasePrice(MarketBasis.Domestic, day.plusDays(1)))
    }

    @Test
    fun `switch waits for the new chart without mixing pricing bases`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val chart = CompletableDeferred<List<MarketObservation>>()
            val clock = Clock.fixed(Instant.parse("2026-11-21T00:00:00Z"), ZoneOffset.UTC)
            val service = object : GoldMarketService {
                override suspend fun fetchQuote(basis: MarketBasis) =
                    MarketQuote(2000.0, 1950.0, 450.0, 7.0, clock.instant())

                override suspend fun fetchHistory(basis: MarketBasis, force: Boolean) = chart.await()
                override suspend fun fetchRealtime(basis: MarketBasis) = RealtimeWindow(5, emptyList())
            }
            val model = MarketViewModel(service, clock)

            model.selectBasis(MarketBasis.International)
            runCurrent()
            assertEquals(MarketBasis.Domestic, model.uiState.value.basis)
            assertNull(model.uiState.value.quote)
            assertEquals(MarketBasis.International, model.uiState.value.pendingBasis)

            chart.complete(listOf(MarketObservation(
                LocalDate.of(2026, 11, 20), MarketGranularity.Daily, 1999.0, 2100.0, 1900.0, 2000.0, "test",
            )))
            runCurrent()

            assertEquals(MarketBasis.International, model.uiState.value.basis)
            assertEquals(450.0, model.uiState.value.quote!!.cnyPerGram!!, 0.001)
            assertTrue(model.uiState.value.visiblePoints(clock.zone).isNotEmpty())
            assertNull(model.uiState.value.pendingBasis)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `historical quote polls deduplicate unchanged quotes and keep observedAt stable on the same day`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val clock = MutableClock(Instant.parse("2026-11-21T01:00:00Z"), ZoneOffset.UTC)
            var currentQuote = MarketQuote(620.0, 615.0, 620.0, null, Instant.parse("2026-11-21T01:00:00Z"))
            val day20 = MarketObservation(LocalDate.of(2026, 11, 20), MarketGranularity.Daily, 610.0, 625.0, 608.0, 615.0, "test")
            val day21 = MarketObservation(LocalDate.of(2026, 11, 21), MarketGranularity.Daily, 615.0, 628.0, 614.0, 622.0, "test")
            val service = object : GoldMarketService {
                override suspend fun fetchQuote(basis: MarketBasis) = currentQuote.copy()
                override suspend fun fetchHistory(basis: MarketBasis, force: Boolean) = listOf(day20.copy(), day21.copy())
                override suspend fun fetchRealtime(basis: MarketBasis) = RealtimeWindow(5, emptyList())
            }
            val model = MarketViewModel(service, clock, computeDispatcher = dispatcher)
            val emissions = mutableListOf<MarketUiState>()
            val collector = launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.toList(emissions) }

            model.refresh()
            runCurrent()
            val afterFirst = model.uiState.value
            val emissionsAfterFirst = emissions.size
            val initialObservations = afterFirst.observations
            val initialQuote = afterFirst.quote
            assertEquals(Instant.parse("2026-11-21T01:00:00Z"), afterFirst.observedAt)
            assertEquals(1, afterFirst.visiblePoints(clock.zone).size)

            // 5 seconds later, identical quote and structurally identical history: zero new emissions, same list/quote refs.
            clock.now = Instant.parse("2026-11-21T01:00:05Z")
            model.refresh()
            runCurrent()
            assertEquals(emissionsAfterFirst, emissions.size)
            assertSame(initialObservations, model.uiState.value.observations)
            assertSame(initialQuote, model.uiState.value.quote)
            assertEquals(Instant.parse("2026-11-21T01:00:00Z"), model.uiState.value.observedAt)

            // Same day, price changes: quote updates, observedAt stays unchanged, observations reference preserved.
            clock.now = Instant.parse("2026-11-21T01:00:10Z")
            currentQuote = MarketQuote(623.5, 615.0, 623.5, null, Instant.parse("2026-11-21T01:00:10Z"))
            model.refresh()
            runCurrent()
            assertEquals(623.5, model.uiState.value.quote!!.cnyPerGram!!, 0.001)
            assertEquals(Instant.parse("2026-11-21T01:00:00Z"), model.uiState.value.observedAt)
            assertSame(initialObservations, model.uiState.value.observations)

            // Crossing midnight updates observedAt/observedDate so 2026-11-21 now becomes yesterday and appears in history.
            clock.now = Instant.parse("2026-11-22T00:00:05Z")
            model.refresh()
            runCurrent()
            assertEquals(LocalDate.of(2026, 11, 22), model.uiState.value.observedDate(clock.zone))
            assertEquals(2, model.uiState.value.visiblePoints(clock.zone).size)

            collector.cancel()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `realtime mode updates observedAt on pause transitions and deduplicates steady paused polls`() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val base = Instant.parse("2026-11-21T02:00:00Z")
            val clock = MutableClock(base, ZoneOffset.UTC)
            var currentQuote = MarketQuote(620.0, 615.0, 620.0, null, base)
            var currentRealtime = RealtimeWindow(
                intervalSeconds = 5,
                points = listOf(
                    MarketChartPoint(base.minusSeconds(60), 619.0),
                    MarketChartPoint(base, 620.0),
                ),
                windowSeconds = 7_200L,
            )
            val service = object : GoldMarketService {
                override suspend fun fetchQuote(basis: MarketBasis) = currentQuote.copy()
                override suspend fun fetchHistory(basis: MarketBasis, force: Boolean) = emptyList<MarketObservation>()
                override suspend fun fetchRealtime(basis: MarketBasis) =
                    currentRealtime.copy(points = currentRealtime.points.map { it.copy() })
            }
            val model = MarketViewModel(service, clock, computeDispatcher = dispatcher)
            model.selectRange(MarketRange.Realtime)
            val emissions = mutableListOf<MarketUiState>()
            val collector = launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.toList(emissions) }

            model.refresh()
            runCurrent()
            assertFalse(model.uiState.value.isRealtimePaused())
            val emissionsWhileActive = emissions.size

            // 5s later (still within 20s tolerance), unchanged quote & realtime -> no emission.
            clock.now = base.plusSeconds(5)
            model.refresh()
            runCurrent()
            assertFalse(model.uiState.value.isRealtimePaused())
            assertEquals(emissionsWhileActive, emissions.size)

            // 25s later (> 20s tolerance), realtime flips to paused -> observedAt updates and state emits.
            clock.now = base.plusSeconds(25)
            model.refresh()
            runCurrent()
            assertTrue(model.uiState.value.isRealtimePaused())
            assertEquals(base.plusSeconds(25), model.uiState.value.observedAt)
            val emissionsOncePaused = emissions.size
            assertTrue(emissionsOncePaused > emissionsWhileActive)

            // 55s later (still paused, same day, unchanged data) -> no redundant emission.
            clock.now = base.plusSeconds(55)
            model.refresh()
            runCurrent()
            assertTrue(model.uiState.value.isRealtimePaused())
            assertEquals(emissionsOncePaused, emissions.size)

            // Market resumes with fresh realtime point and quote -> paused clears and observedAt updates.
            val resumedAt = base.plusSeconds(60)
            clock.now = resumedAt
            currentQuote = MarketQuote(621.0, 615.0, 621.0, null, resumedAt)
            currentRealtime = currentRealtime.copy(
                points = currentRealtime.points + MarketChartPoint(resumedAt, 621.0),
            )
            model.refresh()
            runCurrent()
            assertFalse(model.uiState.value.isRealtimePaused())
            assertEquals(resumedAt, model.uiState.value.observedAt)

            collector.cancel()
        } finally {
            Dispatchers.resetMain()
        }
    }

    private class MutableClock(var now: Instant, private val zoneId: ZoneId) : Clock() {
        override fun getZone(): ZoneId = zoneId
        override fun withZone(zone: ZoneId): Clock = MutableClock(now, zone)
        override fun instant(): Instant = now
    }
}
