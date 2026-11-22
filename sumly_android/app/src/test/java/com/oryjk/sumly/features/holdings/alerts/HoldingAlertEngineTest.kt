package com.oryjk.sumly.features.holdings.alerts

import com.oryjk.sumly.features.holdings.GoldReturnInput
import com.oryjk.sumly.features.market.MarketBasis
import java.time.Instant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HoldingAlertEngineTest {
    private val startedAt = Instant.parse("2026-11-21T02:30:00Z")
    private val input = GoldReturnInput(grams = 1.0, unitPrice = 800.0)
    private val alert = HoldingAlert(kind = HoldingAlertKind.Price, threshold = 800.0, enabled = true, basis = MarketBasis.Domestic)

    @Test
    fun `only a fresh crossing from below fires and cooldown survives rearming`() {
        fun tick(seconds: Long, price: Double, previous: HoldingAlertState): HoldingAlertEvaluation {
            val time = startedAt.plusSeconds(seconds)
            return evaluateHoldingAlert(alert, input, previous, price, time, time)
        }
        val initial = tick(0, 810.0, HoldingAlertState())
        assertFalse(initial.triggered)
        val below = tick(1, 795.0, initial.state)
        assertTrue(below.state.armed)
        val crossed = tick(2, 802.0, below.state)
        assertTrue(crossed.triggered)
        val rearmed = tick(3, 792.0, crossed.state)
        val suppressed = tick(4, 805.0, rearmed.state)
        assertFalse(suppressed.triggered)
        assertEquals(crossed.state.lastTriggeredAt, suppressed.state.lastTriggeredAt)
    }

    @Test
    fun `stale out of order and abnormal jumps never fire`() {
        val baseline = evaluateHoldingAlert(alert, input, HoldingAlertState(), 720.0, startedAt, startedAt).state
        val later = startedAt.plusSeconds(20)
        assertEquals(baseline, evaluateHoldingAlert(alert, input, baseline, 810.0, startedAt, later).state)
        assertFalse(evaluateHoldingAlert(alert, input, baseline, 810.0, later, later.plusSeconds(301)).triggered)
        assertFalse(evaluateHoldingAlert(alert, input, baseline, 900.0, later, later).triggered)
        assertFalse(evaluateHoldingAlert(alert, input, baseline, 810.0, later.plusSeconds(301), later.plusSeconds(301)).triggered)
    }

    @Test
    fun `profit and return targets use the same recovery deductions as portfolio estimates`() {
        val taxed = input.copy(laborFee = 20.0, rule = input.rule.copy(fixedFee = 30.0, perGramDeduction = 5.0))
        val profit = alert.copy(kind = HoldingAlertKind.ProfitAmount, threshold = 100.0)
        val percent = alert.copy(kind = HoldingAlertKind.ReturnPercent, threshold = 100.0 / 820.0 * 100)
        for (candidate in listOf(profit, percent)) {
            val below = evaluateHoldingAlert(candidate, taxed, HoldingAlertState(), 950.0, startedAt, startedAt)
            assertTrue(below.state.armed)
            val later = startedAt.plusSeconds(20)
            assertTrue(evaluateHoldingAlert(candidate, taxed, below.state, 956.0, later, later).triggered)
        }
    }
}
