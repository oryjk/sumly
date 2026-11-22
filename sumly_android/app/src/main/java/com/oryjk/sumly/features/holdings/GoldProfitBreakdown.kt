package com.oryjk.sumly.features.holdings

import java.math.BigDecimal
import java.math.RoundingMode

internal enum class GoldProfitSource(val title: String) {
    Price("金价变化"),
    Purity("纯度折算"),
    Labor("购入工费"),
    OtherCost("其他购入成本"),
    Unitemized("金值与总投入差额"),
    Deduction("每克回收扣减"),
    Discount("回收比例折价"),
    FixedFee("固定卖出费用"),
}

internal data class GoldProfitContribution(val kind: GoldProfitSource, val cents: Long)

internal data class GoldProfitBreakdown(
    val profitCents: Long,
    val sources: List<GoldProfitContribution>,
) {
    companion object {
        fun estimate(inputs: List<GoldReturnInput>, referencePrice: Double?): GoldProfitBreakdown? {
            val price = GoldReturnCalculator.validPrice(referencePrice) ?: return null
            if (inputs.isEmpty()) return null
            val summary = GoldReturnCalculator.aggregate(inputs, price) ?: return null
            val target = summary.profit?.let(::cents) ?: return null
            val totals = mutableMapOf<GoldProfitSource, Double>()

            fun add(kind: GoldProfitSource, amount: Double) {
                if (amount != 0.0) totals[kind] = totals.getOrDefault(kind, 0.0) + amount
            }

            for (input in inputs) {
                val result = GoldReturnCalculator.calculate(input, price) ?: return null
                val goldValue = result.bookValue ?: return null
                val payout = result.proceeds ?: return null
                val nominalValue = price * input.grams
                if (input.totalCostOverride != null || !nominalValue.isFinite()) {
                    add(GoldProfitSource.Unitemized, goldValue - input.totalCost)
                } else {
                    add(GoldProfitSource.Price, nominalValue - input.unitPrice * input.grams)
                    add(GoldProfitSource.Purity, goldValue - nominalValue)
                    add(GoldProfitSource.Labor, -input.laborFee)
                    add(GoldProfitSource.OtherCost, -input.otherCost)
                }
                val deducted = (price - input.rule.perGramDeduction).coerceAtLeast(0.0) * input.effectiveGrams
                val discounted = deducted * (1 - input.rule.discountRate)
                add(GoldProfitSource.Deduction, deducted - goldValue)
                add(GoldProfitSource.Discount, discounted - deducted)
                add(GoldProfitSource.FixedFee, payout - discounted)
            }

            val sources = GoldProfitSource.entries.filter { it in totals }.ifEmpty {
                listOf(if (inputs.any { it.totalCostOverride != null }) GoldProfitSource.Unitemized else GoldProfitSource.Price)
            }
            // Round cumulative boundaries so the displayed contributions reconcile with the summary.
            var sum = 0.0
            var prior = 0L
            val contributions = sources.mapIndexed { index, kind ->
                sum += totals.getOrDefault(kind, 0.0)
                val boundary = if (index == sources.lastIndex) target else cents(sum) ?: return null
                val change = try { Math.subtractExact(boundary, prior) } catch (_: ArithmeticException) { return null }
                prior = boundary
                GoldProfitContribution(kind, change)
            }
            return GoldProfitBreakdown(target, contributions)
        }

        private fun cents(value: Double): Long? = if (value.isFinite()) {
            try {
                BigDecimal.valueOf(value).movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValueExact()
            } catch (_: ArithmeticException) {
                null
            }
        } else null
    }
}
