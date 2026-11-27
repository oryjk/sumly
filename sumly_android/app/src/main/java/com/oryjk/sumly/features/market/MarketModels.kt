package com.oryjk.sumly.features.market

import com.oryjk.sumly.features.holdings.HoldingMarketPurchase
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.log10

enum class MarketBasis(val label: String, val nameInChinese: String, val series: String, val historyUnit: String) {
    Domestic("国内", "国内 Au99.99", "au9999", "CNY/g"),
    International("国际", "国际伦敦金", "xauusd", "USD/troy_oz");

    internal val quotePath: String get() = "$endpoint/quote"
    internal val realtimePath: String get() = "$endpoint/realtime"

    private val endpoint: String
        get() = when (this) {
            Domestic -> "app/market/gold/instruments/au9999"
            // The legacy London endpoint stores sample-time CNY conversions.
            International -> "app/market/gold"
        }
}

enum class MarketRange(val label: String) {
    Realtime("实时"),
    Month("近一月"),
    Quarter("近三月"),
    YearToDate("今年以来"),
    Year("近一年"),
    TwoYears("近两年"),
    ThreeYears("近三年"),
    FiveYears("近五年"),
    TenYears("近十年"),
    History("1900年至今");

    fun labelFor(basis: MarketBasis): String = if (this == History && basis == MarketBasis.Domestic) "全部历史" else label

    internal fun dateBounds(today: LocalDate): ClosedRange<LocalDate>? {
        val end = today.minusDays(1)
        val start = when (this) {
            Realtime -> return null
            Month -> end.minusMonths(1)
            Quarter -> end.minusMonths(3)
            YearToDate -> today.withDayOfYear(1)
            Year -> end.minusYears(1)
            TwoYears -> end.minusYears(2)
            ThreeYears -> end.minusYears(3)
            FiveYears -> end.minusYears(5)
            TenYears -> end.minusYears(10)
            History -> LocalDate.of(1900, 1, 1)
        }
        return if (start <= end) start..end else null
    }
}

enum class ChartScale(val label: String) {
    Linear("线性"), Logarithmic("对数");

    internal fun value(price: Double): Double = if (this == Linear) price else log10(price)
}

data class MarketQuote(
    val price: Double,
    val previousClose: Double?,
    val cnyPerGram: Double?,
    val usdCny: Double?,
    val asOf: Instant,
    val open: Double? = null,
    val high: Double? = null,
    val low: Double? = null,
) {
    val changePercent: Double? get() = previousClose?.let { (price - it) / it * 100 }

    val changePerGram: Double?
        get() = previousCloseCnyPerGram?.let { close -> cnyPerGram?.minus(close) }

    val previousCloseCnyPerGram: Double? get() = inCnyPerGram(previousClose)

    internal fun inCnyPerGram(value: Double?): Double? = value?.let { raw ->
        cnyPerGram?.let { perGram -> (raw / price * perGram).takeIf { it.isFinite() && it > 0 } }
    }
}

enum class MarketGranularity { Annual, Daily, Realtime }

data class MarketChartPoint(
    val time: Instant,
    val price: Double,
    val granularity: MarketGranularity = MarketGranularity.Realtime,
)

data class MarketPurchaseMarker(
    val date: LocalDate,
    val costCnyPerGram: Double,
    val count: Int = 1,
    val items: List<HoldingMarketPurchase> = emptyList(),
)

data class MarketHoldingOverlay(val breakEvenCnyPerGram: Double?, val purchases: List<MarketPurchaseMarker>)

internal data class ResolvedPurchaseMarker(
    val marker: MarketPurchaseMarker,
    val time: Instant,
    val anchorPrice: Double?,
    val interpolated: Boolean,
)

data class RealtimeWindow(
    val intervalSeconds: Int,
    val points: List<MarketChartPoint>,
    val windowSeconds: Long = 1_200L,
)

data class MarketObservation(
    val date: LocalDate,
    val granularity: MarketGranularity,
    val open: Double,
    val high: Double,
    val low: Double,
    val close: Double,
    val source: String,
    val deleted: Boolean = false,
) {
    internal val key: Pair<LocalDate, MarketGranularity> get() = date to granularity
}

internal data class HistorySnapshot(val cursor: String, val observations: List<MarketObservation>)

internal data class HistorySyncPage(
    val series: String,
    val unit: String,
    val cursor: String,
    val reset: Boolean,
    val points: List<MarketObservation>,
) {
    fun merge(basis: MarketBasis, previous: HistorySnapshot?): HistorySnapshot {
        require(series == basis.series && unit == basis.historyUnit && cursor.isNotEmpty() && cursor.length <= 160)
        require(reset || previous != null)
        val uniqueKeys = HashSet<Pair<LocalDate, MarketGranularity>>()
        val merged = if (reset) HashMap() else previous!!.observations.associateByTo(HashMap()) { it.key }
        for (point in points) {
            require(uniqueKeys.add(point.key) && point.source.isNotEmpty())
            require(point.granularity == MarketGranularity.Daily ||
                (point.granularity == MarketGranularity.Annual && basis == MarketBasis.International &&
                    point.date.year in 1900..2015))
            if (point.deleted) {
                merged.remove(point.key)
            } else {
                require(listOf(point.open, point.high, point.low, point.close).all { it.isFinite() && it > 0 })
                merged[point.key] = point
            }
        }
        return HistorySnapshot(cursor, merged.values.sortedWith(compareBy({ it.date }, { it.granularity })))
    }
}

internal const val GRAMS_PER_TROY_OUNCE = 31.1034768

internal object MarketChartLogic {
    const val REALTIME_WINDOW_SECONDS = 1200L
    private const val MAX_SESSION_SECONDS = 24 * 3_600L
    private val sessionGap = Duration.ofHours(6)

    fun historicalPoints(
        observations: List<MarketObservation>,
        basis: MarketBasis,
        range: MarketRange,
        usdCny: Double?,
        now: Instant,
        zone: ZoneId,
    ): List<MarketChartPoint> = historicalPoints(
        observations = observations,
        basis = basis,
        range = range,
        usdCny = usdCny,
        today = now.atZone(zone).toLocalDate(),
        zone = zone,
    )

    fun historicalPoints(
        observations: List<MarketObservation>,
        basis: MarketBasis,
        range: MarketRange,
        usdCny: Double?,
        today: LocalDate,
        zone: ZoneId,
    ): List<MarketChartPoint> {
        val bounds = range.dateBounds(today) ?: return emptyList()
        val rate = when (basis) {
            MarketBasis.Domestic -> 1.0
            MarketBasis.International -> {
                val valid = usdCny?.takeIf { it.isFinite() && it > 0 } ?: return emptyList()
                valid / GRAMS_PER_TROY_OUNCE
            }
        }
        return observations.asSequence()
            .filter { !it.deleted && it.date in bounds }
            .filter { basis != MarketBasis.International || it.granularity == MarketGranularity.Annual || it.date.year >= 2016 }
            .mapNotNull { point ->
                val price = point.close * rate
                if (price.isFinite() && price > 0) {
                    val time = point.date.atTime(LocalTime.NOON).atZone(zone).toInstant()
                    MarketChartPoint(time, price, point.granularity)
                } else null
            }
            .sortedBy { it.time }
            .toList()
    }

    fun realtimePoints(window: RealtimeWindow, now: Instant): List<MarketChartPoint> {
        val byTime = window.points.asSequence()
            .filter { it.time <= now && it.price.isFinite() && it.price > 0 }
            .associateBy { it.time }.values.sortedBy { it.time }
        val latest = byTime.lastOrNull()?.time ?: return emptyList()
        val cutoff = latest.minusSeconds(window.windowSeconds.coerceIn(REALTIME_WINDOW_SECONDS, MAX_SESSION_SECONDS))
        var start = byTime.lastIndex
        while (start > 0) {
            val previous = byTime[start - 1].time
            if (previous < cutoff || Duration.between(previous, byTime[start].time) > sessionGap) break
            start--
        }
        return byTime.subList(start, byTime.size)
    }

    fun mergeRealtime(existing: RealtimeWindow?, incoming: RealtimeWindow, now: Instant): RealtimeWindow? {
        val updates = realtimePoints(incoming, now)
        if (updates.isEmpty()) return null
        val previous = existing?.let { realtimePoints(it, now) }.orEmpty()
        if (previous.isEmpty()) return incoming.copy(points = updates)
        if (previous.last().time > updates.last().time) return existing
        // A complete server session is authoritative. Legacy rolling responses
        // can still extend today's curve while this client is polling.
        if (incoming.windowSeconds > REALTIME_WINDOW_SECONDS) return incoming.copy(points = updates)
        val earlier = previous.takeWhile { it.time < updates.first().time }
        val merged = incoming.copy(points = earlier + updates, windowSeconds = MAX_SESSION_SECONDS)
        return merged.copy(points = realtimePoints(merged, now))
    }

    fun chartSegments(points: List<MarketChartPoint>, intervalSeconds: Int?): List<List<MarketChartPoint>> {
        if (points.isEmpty()) return emptyList()
        if (intervalSeconds == null) return listOf(points)
        val maximumGap = Duration.ofSeconds(maxOf(300L, 3L * intervalSeconds))
        return buildList {
            var start = 0
            for (index in 1 until points.size) {
                if (Duration.between(points[index - 1].time, points[index].time) > maximumGap) {
                    add(points.subList(start, index))
                    start = index
                }
            }
            add(points.subList(start, points.size))
        }
    }

    fun isPaused(latestSample: Instant, latestQuote: Instant?, intervalSeconds: Int, now: Instant): Boolean {
        val tolerance = Duration.ofSeconds(maxOf(20L, intervalSeconds * 2L))
        return Duration.between(latestSample, now) > tolerance ||
            (latestQuote != null && isQuoteStale(latestQuote, now))
    }

    fun isQuoteStale(asOf: Instant, now: Instant): Boolean = Duration.between(asOf, now) > Duration.ofMinutes(3)

    fun resolveMarker(marker: MarketPurchaseMarker, points: List<MarketChartPoint>, zone: ZoneId): ResolvedPurchaseMarker {
        val time = marker.date.atTime(LocalTime.NOON).atZone(zone).toInstant()
        val index = points.binarySearchBy(time) { it.time }
        if (index >= 0) return ResolvedPurchaseMarker(marker, time, points[index].price, false)
        val insertion = -index - 1
        val before = points.getOrNull(insertion - 1)
        val after = points.getOrNull(insertion)
        val price = when {
            before == null -> after?.price
            after == null -> before.price
            else -> {
                // Only this marker's visual anchor is interpolated; the observed series is unchanged.
                val fraction = (time.toEpochMilli() - before.time.toEpochMilli()).toDouble() /
                    (after.time.toEpochMilli() - before.time.toEpochMilli()).toDouble()
                before.price + (after.price - before.price) * fraction
            }
        }
        return ResolvedPurchaseMarker(marker, time, price, price != null)
    }

    fun nearestPoint(points: List<MarketChartPoint>, target: Instant): MarketChartPoint? {
        if (points.isEmpty()) return null
        val result = points.binarySearchBy(target) { it.time }
        if (result >= 0) return points[result]
        val insertion = -result - 1
        val before = points.getOrNull(insertion - 1) ?: return points.first()
        val after = points.getOrNull(insertion) ?: return before
        return if (Duration.between(before.time, target) <= Duration.between(target, after.time)) before else after
    }
}
