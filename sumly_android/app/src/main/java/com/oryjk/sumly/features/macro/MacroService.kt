package com.oryjk.sumly.features.macro

import com.oryjk.sumly.core.network.ApiClient
import java.time.Instant
import java.time.LocalDate
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

internal data class TemperatureFactor(val name: String, val score: Double?, val summary: String)

internal data class TemperatureSnapshot(
    val date: LocalDate?,
    val score: Double?,
    val shortTermLabel: String,
    val longTermScore: Double?,
    val longTermLabel: String,
    val changeOneDay: Double?,
    val volatilityNote: String?,
    val degraded: Boolean,
    val factors: List<TemperatureFactor>,
) {
    val badge: Int? get() = score?.roundToInt()
}

internal enum class MacroRange(val query: String, val title: String) {
    OneYear("1y", "1年"), ThreeYears("3y", "3年"), FiveYears("5y", "5年"),
    TenYears("10y", "10年"), All("all", "全部"),
}

internal data class MacroPoint(val date: LocalDate, val value: Double)
internal data class MacroCotPoint(
    val date: LocalDate,
    val managedNet: Double,
    val swapNet: Double,
    val openInterest: Double,
    val managedRatio: Double?,
)
internal data class MacroCotReport(val latest: MacroCotPoint?, val points: List<MacroCotPoint>)
internal data class TemperatureHistory(val temperature: List<MacroPoint>, val gold: List<MacroPoint>)
internal data class MacroMetric(
    val title: String,
    val value: Double?,
    val unit: String,
    val date: LocalDate? = null,
    val seriesId: String? = null,
)
internal data class MacroSection(val title: String, val metrics: List<MacroMetric>)
internal data class TreasuryReport(
    val summary: MacroSection,
    val indicators: MacroSection,
    val debt: List<MacroPoint>,
    val realYield: List<MacroPoint>,
    val nominalYield: List<MacroPoint>,
)
internal data class MacroPercentile(val window: String, val percentile: Double?, val count: Int)
internal data class MacroIndicatorDetail(
    val metric: MacroMetric,
    val note: String,
    val source: String,
    val frequency: String,
    val goldRelation: String,
    val syncStatus: String,
    val lastSyncedAt: Instant?,
    val percentiles: List<MacroPercentile>,
    val changes: List<MacroMetric>,
    val observations: List<MacroPoint>,
)

internal interface MacroService {
    suspend fun temperature(): TemperatureSnapshot
    suspend fun temperatureHistory(range: MacroRange): TemperatureHistory
    suspend fun treasury(range: MacroRange): TreasuryReport
    suspend fun indicators(): List<MacroSection>
    suspend fun goldCot(range: MacroRange): MacroCotReport
    suspend fun indicator(seriesId: String, range: MacroRange): MacroIndicatorDetail
}

internal class BackendMacroService(private val api: ApiClient) : MacroService {
    override suspend fun temperature(): TemperatureSnapshot {
        val response = api.get("app/macro/temperature")
        val date = response.day("as_of")
        val factors = response.optJSONArray("dimensions").objects().mapNotNull { factor ->
            val name = factor.optString("name").takeIf(String::isNotBlank) ?: return@mapNotNull null
            TemperatureFactor(name, factor.number("score")?.takeIf { factor.optBoolean("available") }, factor.optString("summary"))
        }
        val score = response.number("score")?.coerceIn(0.0, 100.0)
            ?.takeIf { date != null && (factors.isEmpty() || factors.any { it.score != null }) }
        val regime = response.optJSONObject("macro_regime")
        return TemperatureSnapshot(
            date = date,
            score = score,
            shortTermLabel = when (score) {
                null -> "暂无数据"
                in 0.0..<20.0 -> "极冷区间"
                in 20.0..<40.0 -> "偏冷区间"
                in 40.0..<60.0 -> "中性区间"
                in 60.0..<80.0 -> "偏热区间"
                else -> "极热区间"
            },
            longTermScore = regime?.number("score")?.coerceIn(0.0, 100.0)?.takeIf { date != null },
            longTermLabel = when (regime?.optString("regime")) {
                "tailwind" -> "支撑偏强"
                "headwind" -> "支撑偏弱"
                else -> "背景中性"
            },
            changeOneDay = response.number("change_1d")?.takeIf { score != null },
            volatilityNote = response.optString("volatility_note").takeIf {
                response.optBoolean("volatility_alert") && it.isNotBlank() && score != null
            },
            degraded = response.optBoolean("degraded"),
            factors = factors,
        )
    }

    override suspend fun temperatureHistory(range: MacroRange): TemperatureHistory {
        val rows = history("app/macro/temperature/history", range).getJSONArray("points")
        return TemperatureHistory(
            temperature = rows.points("score") { it in 0.0..100.0 },
            gold = rows.points("gold_price_usd") { it > 0 },
        )
    }

    override suspend fun treasury(range: MacroRange): TreasuryReport {
        val response = history("app/macro/treasury", range)
        val summary = response.getJSONObject("summary")
        val date = response.day("as_of")
        val metrics = listOf(
            MacroMetric("美债总规模", summary.number("total_debt_trillion_usd"), "万亿美元", date),
            MacroMetric("同比变化", summary.number("debt_change_yoy_trillion"), "万亿美元", date),
            MacroMetric("国债 / GDP", summary.number("debt_to_gdp_pct"), "%", date),
            MacroMetric("利息 / 财政收入", summary.number("interest_to_revenue_pct"), "%", date),
            MacroMetric("财政压力指数", summary.number("fiscal_stress_score"), "分", date),
            MacroMetric("10 年期名义利率", summary.number("yield_10y_nominal_pct"), "%", date),
            MacroMetric("10 年期实际利率", summary.number("yield_10y_real_pct"), "%", date),
            MacroMetric("10 年期与 2 年期利差", summary.number("spread_10y_2y_pct"), "个百分点", date),
        )
        return TreasuryReport(
            summary = MacroSection("美国国债", metrics),
            indicators = MacroSection("相关指标", response.optJSONArray("cards").objects().mapNotNull(::metric)),
            debt = response.optJSONArray("debt_series").points(),
            realYield = response.optJSONArray("real_yield_series").points(),
            nominalYield = response.optJSONArray("nominal_yield_series").points(),
        )
    }

    override suspend fun indicators(): List<MacroSection> = api.get("app/macro/indicators")
        .optJSONArray("sections").objects().mapNotNull { section ->
            val name = section.optString("name_zh").takeIf(String::isNotBlank) ?: return@mapNotNull null
            val indicators = section.optJSONArray("indicators").objects().mapNotNull(::metric)
            MacroSection(name, indicators)
        }

    override suspend fun goldCot(range: MacroRange): MacroCotReport {
        val response = history("app/macro/cot/gold", range)
        val points = response.optJSONArray("points").objects().mapNotNull(::cotPoint)
            .distinctBy(MacroCotPoint::date).sortedBy(MacroCotPoint::date)
        return MacroCotReport(response.optJSONObject("latest")?.let(::cotPoint) ?: points.lastOrNull(), points)
    }

    override suspend fun indicator(seriesId: String, range: MacroRange): MacroIndicatorDetail {
        val response = history("app/macro/indicators/$seriesId", range)
        val indicator = requireNotNull(metric(response))
        require(indicator.seriesId == seriesId)
        return MacroIndicatorDetail(
            metric = indicator,
            note = response.optString("plain_note"),
            source = response.optString("source"),
            frequency = response.optString("frequency"),
            goldRelation = response.optString("gold_relation"),
            syncStatus = response.optString("sync_status"),
            lastSyncedAt = runCatching { Instant.parse(response.optString("last_synced_at")) }.getOrNull(),
            percentiles = response.optJSONArray("percentiles").objects().mapNotNull {
                val window = it.optString("window").takeIf(String::isNotBlank) ?: return@mapNotNull null
                MacroPercentile(window, it.number("percentile")?.takeIf { value -> value in 0.0..100.0 }, it.optInt("observation_count"))
            },
            changes = listOf(
                MacroMetric("近5日", response.number("change_5d"), indicator.unit),
                MacroMetric("近20日", response.number("change_20d"), indicator.unit),
                MacroMetric("近3月", response.number("change_3m"), indicator.unit),
                MacroMetric("同比", response.number("change_yoy"), indicator.unit),
            ),
            observations = response.getJSONArray("observations").points(),
        )
    }

    private suspend fun history(path: String, range: MacroRange): JSONObject =
        api.get(path, mapOf("range" to range.query), maxResponseBytes = 4L * 1024 * 1024)

    private fun metric(row: JSONObject): MacroMetric? {
        val title = row.optString("name_zh").takeIf(String::isNotBlank) ?: return null
        return MacroMetric(
            title, row.number("latest_value"), unit(row.optString("unit")), row.day("latest_date"),
            row.optString("series_id").takeIf { it.matches(SeriesId) },
        )
    }

    private fun cotPoint(row: JSONObject): MacroCotPoint? {
        val date = row.day("date") ?: return null
        val managed = row.number("mm_net") ?: return null
        val swap = row.number("swap_net") ?: return null
        val total = row.number("open_interest")?.takeIf { it >= 0 } ?: return null
        return MacroCotPoint(date, managed, swap, total, row.number("mm_net_ratio_pct"))
    }

    private fun unit(raw: String): String = when (raw) {
        "trillion_usd" -> "万亿美元"
        "billion_usd" -> "十亿美元"
        "million_usd" -> "百万美元"
        "usd" -> "美元"
        "usd_per_oz" -> "美元/盎司"
        "pct", "percent" -> "%"
        "tonnes", "tons" -> "吨"
        "contracts" -> "张"
        "index", "points" -> "点"
        else -> raw
    }

    private companion object {
        val SeriesId = Regex("[A-Za-z0-9_-]+")
    }
}

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else {
    (0 until length()).mapNotNull(::optJSONObject)
}

private fun JSONObject.number(key: String): Double? = optDouble(key).takeIf(Double::isFinite)
private fun JSONObject.day(key: String): LocalDate? = runCatching { LocalDate.parse(optString(key)) }.getOrNull()

private fun JSONArray?.points(key: String = "value", valid: (Double) -> Boolean = { true }): List<MacroPoint> =
    objects().mapNotNull { row ->
        val date = row.day("date") ?: return@mapNotNull null
        val value = row.number(key)?.takeIf(valid) ?: return@mapNotNull null
        MacroPoint(date, value)
    }.distinctBy(MacroPoint::date).sortedBy(MacroPoint::date)
