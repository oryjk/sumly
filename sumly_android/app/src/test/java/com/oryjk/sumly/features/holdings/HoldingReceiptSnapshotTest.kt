package com.oryjk.sumly.features.holdings

import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

class HoldingReceiptSnapshotTest {
    @Test
    fun `receipt counts only active purchases in the destination book and keeps the highest milestone crossed`() {
        val purchase = HoldingRecord(
            input = GoldReturnInput(grams = 12.0, unitPrice = 700.0, totalCostOverride = 8_500.0),
            timestamp = Instant.parse("2026-11-21T12:00:00Z"),
            bookName = "测试账本",
        )
        val existing = purchase.copy(id = UUID.randomUUID(), input = purchase.input.copy(grams = 0.5))
        val sold = purchase.copy(id = UUID.randomUUID(), disposition = HoldingDisposition.Sold)
        val otherBook = purchase.copy(id = UUID.randomUUID(), bookName = "另一个账本")
        val committed = HoldingsSnapshot(records = listOf(purchase, existing, sold, otherBook))

        val receipt = HoldingReceiptSnapshot.from(purchase, committed)

        assertEquals(2, receipt.purchaseSequence)
        assertEquals(12.5, receipt.totalBookGrams, 0.0)
        assertEquals(8_500.0, receipt.totalCost, 0.0)
        assertEquals("10g 初成", receipt.newMilestone)
        assertEquals("50g 筑底", receipt.nextMilestone)
        assertEquals(37.5, receipt.remainingGrams, 0.0)
        assertEquals(0.25f, receipt.progress, 0.0f)
    }
}
