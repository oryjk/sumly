package com.oryjk.sumly.features.market

import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
