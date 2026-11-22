package com.oryjk.sumly.features.market

import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
