package com.oryjk.sumly.features.holdings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GoldProfitBreakdownTest {
    @Test
    fun `recovery effects follow the payout floor`() {
        val holding = GoldReturnInput(
            grams = 10.0, purity = 0.9, unitPrice = 300.0, laborFee = 20.0, otherCost = 5.0,
            rule = GoldRecoveryRule(perGramDeduction = 10.0, discountRate = 0.1, fixedFee = 10_000.0),
        )
        val breakdown = requireNotNull(GoldProfitBreakdown.estimate(listOf(holding), 400.0))
        val entries = breakdown.sources.associate { it.kind to it.cents }
        assertEquals(100_000L, entries[GoldProfitSource.Price])
        assertEquals(-40_000L, entries[GoldProfitSource.Purity])
        assertEquals(-315_900L, entries[GoldProfitSource.FixedFee])
        assertEquals(-302_500L, breakdown.profitCents)
        assertEquals(breakdown.profitCents, breakdown.sources.sumOf { it.cents })
    }

    @Test
    fun `manual totals remain combined and cent values reconcile with portfolio result`() {
        val holding = GoldReturnInput(
            grams = 1.1, purity = 0.9999, unitPrice = 300.0, laborFee = 20.0, otherCost = 5.0,
            totalCostOverride = 450.035, rule = GoldRecoveryRule(3.011, 0.0007, 0.123),
        )
        val breakdown = requireNotNull(GoldProfitBreakdown.estimate(listOf(holding), 400.0))
        assertEquals(
            listOf(GoldProfitSource.Unitemized, GoldProfitSource.Deduction, GoldProfitSource.Discount, GoldProfitSource.FixedFee),
            breakdown.sources.map { it.kind },
        )
        assertEquals(breakdown.profitCents, breakdown.sources.sumOf { it.cents })
        assertNull(GoldProfitBreakdown.estimate(listOf(holding), null))
    }
}
