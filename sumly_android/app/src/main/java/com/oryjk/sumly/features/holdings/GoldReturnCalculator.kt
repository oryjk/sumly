package com.oryjk.sumly.features.holdings

data class GoldRecoveryRule(
    val perGramDeduction: Double = 0.0,
    val discountRate: Double = 0.0,
    val fixedFee: Double = 0.0,
) {
    val isValid: Boolean
        get() = perGramDeduction.isFinite() && perGramDeduction >= 0.0 &&
            discountRate >= 0.0 && discountRate < 1.0 &&
            fixedFee.isFinite() && fixedFee >= 0.0
}

data class GoldReturnInput(
    val grams: Double,
    val purity: Double = 1.0,
    val unitPrice: Double,
    val laborFee: Double = 0.0,
    val otherCost: Double = 0.0,
    val totalCostOverride: Double? = null,
    val rule: GoldRecoveryRule = GoldRecoveryRule(),
) {
    val totalCost: Double get() = totalCostOverride ?: (grams * unitPrice + laborFee + otherCost)
    val effectiveGrams: Double get() = grams * purity

    val isValid: Boolean
        get() = grams.isFinite() && grams > 0.0 && purity > 0.0 && purity <= 1.0 &&
            unitPrice.isFinite() && unitPrice >= 0.0 &&
            laborFee.isFinite() && laborFee >= 0.0 && otherCost.isFinite() && otherCost >= 0.0 &&
            totalCost.isFinite() && totalCost >= 0.0 && effectiveGrams > 0.0 && rule.isValid
}

data class GoldReturnResult(
    val totalCost: Double,
    val effectiveGrams: Double,
    val bookValue: Double?,
    val recoveryUnitPrice: Double?,
    val proceeds: Double?,
    val profit: Double?,
    val profitPercent: Double?,
    val breakEvenPrice: Double,
    val priceDistance: Double?,
    val requiredRisePercent: Double?,
    val comprehensiveUnitCost: Double,
    val premiumPerGram: Double?,
)

data class GoldPortfolioReturn(
    val grams: Double,
    val totalCost: Double,
    val bookValue: Double?,
    val proceeds: Double?,
    val profit: Double?,
    val profitPercent: Double?,
    val breakEvenPrice: Double?,
    val todayChange: Double?,
)

object GoldReturnCalculator {
    fun validPrice(price: Double?): Double? = price?.takeIf { it.isFinite() && it > 0.0 }

    fun referencePrice(input: GoldReturnInput, targetProceeds: Double): Double? {
        if (!input.isValid || !targetProceeds.isFinite() || targetProceeds < 0.0) return null
        if (targetProceeds == 0.0) return 0.0
        val rule = input.rule
        val price = (targetProceeds + rule.fixedFee) / (input.effectiveGrams * (1 - rule.discountRate)) +
            rule.perGramDeduction
        return price.takeIf(Double::isFinite)
    }

    fun calculate(input: GoldReturnInput, referencePrice: Double?): GoldReturnResult? {
        val cost = input.totalCost
        val weight = input.effectiveGrams
        val rule = input.rule
        val breakEven = referencePrice(input, targetProceeds = cost) ?: return null
        val price = validPrice(referencePrice)
        val bookValue = price?.times(weight)
        val recoveryUnitPrice = price?.let { recoveryUnitPrice(rule, it) }
        val proceeds = price?.let { proceeds(input, it) }
        val profit = proceeds?.minus(cost)
        val profitPercent = profit?.takeIf { cost > 0.0 }?.let { it / cost * 100 }
        val priceDistance = price?.minus(breakEven)
        val requiredRisePercent = price?.let { (breakEven / it - 1).coerceAtLeast(0.0) * 100 }
        val comprehensiveUnitCost = cost / input.grams
        val premiumPerGram = price?.let { comprehensiveUnitCost - it }
        if (!listOfNotNull(bookValue, proceeds, profitPercent, priceDistance, requiredRisePercent,
                comprehensiveUnitCost, premiumPerGram).all(Double::isFinite)
        ) return null
        return GoldReturnResult(
            cost, weight, bookValue, recoveryUnitPrice, proceeds, profit, profitPercent, breakEven,
            priceDistance, requiredRisePercent, comprehensiveUnitCost, premiumPerGram,
        )
    }

    fun aggregate(
        inputs: List<GoldReturnInput>,
        referencePrice: Double?,
        previousPrice: Double? = null,
    ): GoldPortfolioReturn? {
        val results = inputs.map { calculate(it, referencePrice) ?: return null }
        val cost = results.sumOf { it.totalCost }
        val grams = inputs.sumOf { it.grams }
        val hasQuote = validPrice(referencePrice) != null && inputs.isNotEmpty()
        val proceeds = if (hasQuote) results.sumOf { it.proceeds ?: 0.0 } else null
        val value = if (hasQuote) results.sumOf { it.bookValue ?: 0.0 } else null
        val profit = proceeds?.minus(cost)
        val percent = profit?.takeIf { cost > 0.0 }?.let { it / cost * 100 }
        val previous = validPrice(previousPrice)?.takeIf { hasQuote }?.let { price ->
            inputs.sumOf { proceeds(it, price) }
        }
        val todayChange = previous?.let { (proceeds ?: 0.0) - it }
        if (!listOfNotNull(proceeds, value, profit, percent, todayChange, cost, grams)
                .all(Double::isFinite)
        ) return null
        val breakEven = results.maxOfOrNull { it.breakEvenPrice }?.let { maxBreakEven ->
            // Every item has its own zero floor, so the midpoint must be tested against total proceeds.
            var low = 0.0
            var high = maxBreakEven
            repeat(80) {
                val middle = low + (high - low) / 2
                if (inputs.sumOf { proceeds(it, middle) } >= cost) high = middle else low = middle
            }
            high
        }
        return GoldPortfolioReturn(grams, cost, value, proceeds, profit, percent, breakEven, todayChange)
    }

    private fun recoveryUnitPrice(rule: GoldRecoveryRule, price: Double): Double =
        (price - rule.perGramDeduction).coerceAtLeast(0.0) * (1 - rule.discountRate)

    private fun proceeds(input: GoldReturnInput, price: Double): Double =
        (recoveryUnitPrice(input.rule, price) * input.effectiveGrams - input.rule.fixedFee).coerceAtLeast(0.0)
}
