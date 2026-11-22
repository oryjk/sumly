package com.oryjk.sumly.features.holdings.alerts

import com.oryjk.sumly.features.holdings.GoldReturnCalculator
import com.oryjk.sumly.features.holdings.GoldReturnInput
import com.oryjk.sumly.features.market.MarketBasis
import java.time.Instant
import java.util.UUID
import kotlin.math.abs

enum class HoldingAlertKind(val key: String, val title: String, val field: String?, val defaultThreshold: Double) {
    BreakEven("breakEven", "达到真实保本", null, 0.0),
    ReturnPercent("returnPercent", "真实收益率目标", "收益率目标（%）", 10.0),
    ProfitAmount("profitAmount", "预计盈利金额目标", "预计盈利（元）", 3_000.0),
    Price("price", "参考金价目标", "参考金价（元/克）", 900.0),
}

data class HoldingAlert(
    val id: UUID = UUID.randomUUID(),
    val kind: HoldingAlertKind,
    val threshold: Double,
    val enabled: Boolean,
    val basis: MarketBasis,
) {
    val isValid: Boolean get() = threshold.isFinite() && threshold >= 0.0
    internal val canCheck: Boolean get() = enabled && isValid && (kind != HoldingAlertKind.Price || threshold > 0.0)
}

internal data class HoldingAlertState(
    val previousPrice: Double? = null,
    val previousAsOf: Instant? = null,
    val armed: Boolean = false,
    val lastTriggeredAt: Instant? = null,
)

internal data class HoldingAlertEvaluation(val state: HoldingAlertState, val triggered: Boolean = false)

internal fun evaluateHoldingAlert(
    alert: HoldingAlert,
    input: GoldReturnInput,
    previous: HoldingAlertState,
    price: Double,
    asOf: Instant,
    now: Instant,
): HoldingAlertEvaluation {
    if (!alert.canCheck || GoldReturnCalculator.validPrice(price) == null ||
        asOf < now.minusSeconds(300) || asOf > now.plusSeconds(60) ||
        previous.previousAsOf?.let { asOf <= it } == true
    ) return HoldingAlertEvaluation(previous)
    val result = GoldReturnCalculator.calculate(input, price) ?: return HoldingAlertEvaluation(previous)
    val baseline = if (previous.previousAsOf?.let { asOf > it.plusSeconds(300) } == true) {
        HoldingAlertState(lastTriggeredAt = previous.lastTriggeredAt)
    } else previous
    if (baseline.previousPrice?.let { abs(price / it - 1) > 0.2 } == true) return HoldingAlertEvaluation(previous)

    val target = when (alert.kind) {
        HoldingAlertKind.BreakEven -> result.breakEvenPrice
        HoldingAlertKind.Price -> alert.threshold
        HoldingAlertKind.ProfitAmount -> GoldReturnCalculator.referencePrice(input, input.totalCost + alert.threshold)
        HoldingAlertKind.ReturnPercent -> input.totalCost.takeIf { it > 0.0 }?.let {
            GoldReturnCalculator.referencePrice(input, it * (1 + alert.threshold / 100))
        }
    } ?: return HoldingAlertEvaluation(previous)
    val crossing = baseline.armed && price >= target
    val armed = !crossing && (baseline.armed || price < target - maxOf(0.01, target * 0.001))
    val triggered = crossing && (baseline.lastTriggeredAt?.let { now >= it.plusSeconds(86_400) } ?: true)
    return HoldingAlertEvaluation(
        HoldingAlertState(price, asOf, armed, if (triggered) now else baseline.lastTriggeredAt),
        triggered,
    )
}
