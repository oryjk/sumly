package com.oryjk.sumly.features.macro

import com.oryjk.sumly.core.network.ApiClient
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MacroServiceTest {
    @Test
    fun goldCotKeepsNetShortPositionsAndFallsBackToLatestObservation() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody(
                """{"code":0,"data":{"points":[
                    {"date":"2026-11-17","mm_net":1000,"swap_net":-650,"open_interest":3400,"mm_net_ratio_pct":29.4},
                    {"date":"2026-11-10","mm_net":-250,"swap_net":100,"open_interest":3500}]}}""",
            ))
            val report = BackendMacroService(ApiClient(server.url("/api/v1/").toString()))
                .goldCot(MacroRange.OneYear)

            assertEquals("/api/v1/app/macro/cot/gold?range=1y", server.takeRequest().path)
            assertEquals(listOf(-250.0, 1000.0), report.points.map { it.managedNet })
            assertEquals(-650.0, requireNotNull(report.latest).swapNet, 0.0)
        }
    }

    @Test
    fun historyKeepsMissingGoldPricesSeparateFromTemperatureScores() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody(
                """{"code":0,"data":{"points":[
                    {"date":"2026-11-21","score":30,"gold_price_usd":2050.5},
                    {"date":"2026-11-20","score":0,"gold_price_usd":null}]}}""",
            ))
            val history = BackendMacroService(ApiClient(server.url("/api/v1/").toString()))
                .temperatureHistory(MacroRange.ThreeYears)

            assertEquals("/api/v1/app/macro/temperature/history?range=3y", server.takeRequest().path)
            assertEquals(listOf(0.0, 30.0), history.temperature.map { it.value })
            assertEquals(listOf(2050.5), history.gold.map { it.value })
            assertEquals("2026-11-21", history.gold.single().date.toString())
        }
    }

    @Test
    fun indicatorDetailUsesSelectedRangeAndKeepsNegativeObservations() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody(
                """{"code":0,"data":{"series_id":"DFII10","name_zh":"实际利率","unit":"pct",
                    "observations":[{"date":"2026-11-20","value":-0.1},{"date":"unknown","value":4}]}}""",
            ))
            val detail = BackendMacroService(ApiClient(server.url("/api/v1/").toString()))
                .indicator("DFII10", MacroRange.TenYears)

            assertEquals("/api/v1/app/macro/indicators/DFII10?range=10y", server.takeRequest().path)
            assertEquals("实际利率", detail.metric.title)
            assertEquals("%", detail.metric.unit)
            assertEquals(listOf(-0.1), detail.observations.map { it.value })
        }
    }

    @Test
    fun temperatureKeepsShortTermHeatSeparateFromLongTermRegime() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody(
                """{"code":0,"data":{"as_of":"2026-11-20","score":27.1,"level":"cool",
                    "macro_regime":{"score":66.9,"regime":"tailwind"},
                    "dimensions":[{"name":"趋势与动量","score":6.5,"available":true}]}}""",
            ))

            val snapshot = BackendMacroService(ApiClient(server.url("/sumly/api/v1/").toString())).temperature()

            assertEquals("/sumly/api/v1/app/macro/temperature", server.takeRequest().path)
            assertEquals(27, snapshot.badge)
            assertEquals("偏冷区间", snapshot.shortTermLabel)
            assertEquals(66.9, requireNotNull(snapshot.longTermScore), 0.0)
            assertEquals("支撑偏强", snapshot.longTermLabel)
        }
    }

    @Test
    fun coldStartWithoutObservationsDoesNotShowZeroDegrees() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody(
                """{"code":0,"data":{"as_of":"","score":0,"level":"freezing",
                    "dimensions":[{"name":"趋势与动量","score":0,"available":false}]}}""",
            ))

            val snapshot = BackendMacroService(ApiClient(server.url("/api/v1/").toString())).temperature()

            assertNull(snapshot.badge)
            assertNull(snapshot.factors.single().score)
        }
    }
}
