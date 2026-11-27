package com.oryjk.sumly.features.market

import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.core.network.ApiException
import java.time.Instant
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class MarketPayloadTest {
    @Test
    fun `quote keeps upstream date and leaves unavailable conversion absent`() {
        val quote = MarketPayload.quote(JSONObject("""{
            "price": 2010.0, "prev_close": 2000, "usd_cny": 0, "cny_per_gram": 0,
            "as_of": "2026-11-21T04:00:00+08:00"
        }"""))

        assertEquals(Instant.parse("2026-11-20T20:00:00Z"), quote.asOf)
        assertEquals(0.5, quote.changePercent!!, 0.00001)
        assertNull(quote.cnyPerGram)
        assertNull(quote.usdCny)
    }

    @Test
    fun `real time minute response keeps timestamped server observations only`() {
        val result = MarketPayload.realtime(JSONObject("""{
            "unit": "CNY/g", "interval_seconds": 60, "window_seconds": 1200,
            "points": [
              {"time": "2026-11-21T04:03:00+08:00", "price": 910},
              {"time": "2026-11-21T04:00:00+08:00", "price": 900},
              {"time": "not-a-time", "price": 990}
            ]
        }"""))

        assertEquals(60, result.intervalSeconds)
        assertEquals(listOf(900.0, 910.0), result.points.map { it.price })
    }

    @Test(expected = IllegalArgumentException::class)
    fun `real time endpoint rejects unconverted London ounces`() {
        MarketPayload.realtime(JSONObject("""{
            "unit": "USD/troy_oz", "interval_seconds": 5, "window_seconds": 1200, "points": []
        }"""))
    }

    @Test
    fun `session payload accepts the expanded range and real backend points`() {
        val result = MarketPayload.realtime(JSONObject("""{
            "unit": "CNY/g", "interval_seconds": 60, "window_seconds": 21600,
            "points": [
              {"time": "2026-11-20T23:00:00+08:00", "price": 902},
              {"time": "2026-11-21T04:59:00+08:00", "price": 897}
            ]
        }"""))

        assertEquals(21600L, result.windowSeconds)
        assertEquals(listOf(902.0, 897.0), result.points.map { it.price })
    }

    @Test
    fun `realtime fetch requests window day first and falls back to session then default on 422 or 400`() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(422).setBody("""{"code":422,"message":"invalid window; allowed: 20m, session"}"""))
            server.enqueue(MockResponse().setBody("""{
                "code": 0, "message": "ok",
                "data": {
                    "unit": "CNY/g", "interval_seconds": 60, "window_seconds": 21600,
                    "points": [{"time": "2026-11-27T20:02:00+08:00", "price": 785.0}]
                }
            }"""))
            val service = BackendGoldMarketService(ApiClient(server.url("/api/v1/").toString()))

            val window = service.fetchRealtime(MarketBasis.Domestic)

            assertEquals(21600L, window.windowSeconds)
            assertEquals(listOf(785.0), window.points.map { it.price })
            val first = server.takeRequest()
            val second = server.takeRequest()
            assertEquals("/api/v1/app/market/gold/instruments/au9999/realtime", first.requestUrl?.encodedPath)
            assertEquals("day", first.requestUrl?.queryParameter("window"))
            assertEquals("session", second.requestUrl?.queryParameter("window"))
        }

        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(422).setBody("""{"code":422,"message":"invalid window"}"""))
            server.enqueue(MockResponse().setResponseCode(400).setBody("""{"code":400,"message":"invalid window"}"""))
            server.enqueue(MockResponse().setBody("""{
                "code": 0, "message": "ok",
                "data": {
                    "unit": "CNY/g", "interval_seconds": 5, "window_seconds": 1200,
                    "points": [{"time": "2026-11-27T20:02:00+08:00", "price": 786.0}]
                }
            }"""))
            val service = BackendGoldMarketService(ApiClient(server.url("/api/v1/").toString()))

            val window = service.fetchRealtime(MarketBasis.International)

            assertEquals(1200L, window.windowSeconds)
            assertEquals("day", server.takeRequest().requestUrl?.queryParameter("window"))
            assertEquals("session", server.takeRequest().requestUrl?.queryParameter("window"))
            assertNull(server.takeRequest().requestUrl?.queryParameter("window"))
        }
    }

    @Test
    fun `realtime fetch does not fall back on server 500 error`() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(500).setBody("""{"code":500,"message":"internal"}"""))
            val service = BackendGoldMarketService(ApiClient(server.url("/api/v1/").toString()))

            val failure = assertThrows(ApiException::class.java) {
                runBlocking { service.fetchRealtime(MarketBasis.Domestic) }
            }

            assertEquals(500, failure.httpStatus)
            assertEquals(1, server.requestCount)
        }
    }
}
