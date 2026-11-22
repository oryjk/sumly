package com.oryjk.sumly.features.market

import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import org.json.JSONArray
import org.json.JSONObject

internal object MarketPayload {
    fun quote(payload: JSONObject): MarketQuote = MarketQuote(
        price = requireNotNull(payload.positiveNumber("price")),
        previousClose = payload.positiveNumber("prev_close"),
        cnyPerGram = payload.positiveNumber("cny_per_gram"),
        usdCny = payload.positiveNumber("usd_cny"),
        asOf = requireNotNull(parseTime(payload.getString("as_of"))),
        open = payload.positiveNumber("open"),
        high = payload.positiveNumber("high"),
        low = payload.positiveNumber("low"),
    )

    fun realtime(payload: JSONObject): RealtimeWindow {
        val interval = payload.getInt("interval_seconds")
        val windowSeconds = payload.getLong("window_seconds")
        require(payload.getString("unit") == "CNY/g" && (interval == 5 || interval == 60) &&
            windowSeconds in MarketChartLogic.REALTIME_WINDOW_SECONDS..86_400)
        val source = payload.getJSONArray("points")
        require(source.length() <= 86_400 / 5 + 1)
        val points = buildList {
            for (index in 0 until source.length()) {
                val raw = source.optJSONObject(index) ?: continue
                val time = parseTime(raw.optString("time")) ?: continue
                val price = raw.positiveNumber("price") ?: continue
                add(MarketChartPoint(time, price))
            }
        }
        return RealtimeWindow(interval, points.sortedBy { it.time }, windowSeconds)
    }

    fun history(payload: JSONObject): HistorySyncPage = HistorySyncPage(
        series = payload.getString("series"),
        unit = payload.getString("unit"),
        cursor = payload.getString("cursor"),
        reset = payload.getBoolean("reset"),
        points = parseObservations(payload.getJSONArray("points")),
    )

    fun historyRecord(basis: MarketBasis, snapshot: HistorySnapshot, checkedAt: Instant): JSONObject = JSONObject()
        .put("series", basis.series)
        .put("unit", basis.historyUnit)
        .put("cursor", snapshot.cursor)
        .put("reset", true)
        .put("checked_at", checkedAt.toEpochMilli())
        .put("points", JSONArray().apply {
            for (point in snapshot.observations) {
                put(JSONObject()
                    .put("date", point.date.toString())
                    .put("granularity", if (point.granularity == MarketGranularity.Annual) "annual" else "daily")
                    .put("open", point.open)
                    .put("high", point.high)
                    .put("low", point.low)
                    .put("close", point.close)
                    .put("source", point.source)
                    .put("deleted", false))
            }
        })

    private fun parseObservations(values: JSONArray): List<MarketObservation> = List(values.length()) { index ->
        val item = values.getJSONObject(index)
        MarketObservation(
            date = LocalDate.parse(item.getString("date")),
            granularity = when (item.getString("granularity")) {
                "daily" -> MarketGranularity.Daily
                "annual" -> MarketGranularity.Annual
                else -> throw IllegalArgumentException("Unsupported market history granularity")
            },
            open = item.getDouble("open"),
            high = item.getDouble("high"),
            low = item.getDouble("low"),
            close = item.getDouble("close"),
            source = item.getString("source"),
            deleted = item.getBoolean("deleted"),
        )
    }

    private fun JSONObject.positiveNumber(key: String): Double? = optDouble(key).takeIf { it.isFinite() && it > 0 }

    private fun parseTime(value: String): Instant? = try {
        OffsetDateTime.parse(value).toInstant()
    } catch (_: DateTimeParseException) {
        null
    }
}
