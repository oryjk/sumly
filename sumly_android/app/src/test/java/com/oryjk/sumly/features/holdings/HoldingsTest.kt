package com.oryjk.sumly.features.holdings

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HoldingsTest {
    private val purchaseDate = Instant.parse("2026-11-19T17:00:00Z")
    private val purchaseId = UUID.fromString("b92d42c7-026c-4ca9-a85c-53047555336b")
    private val disposalId = UUID.fromString("fd719602-6a9c-4dc5-9466-0e0be7515f4c")

    @Test
    fun cashTotalDoesNotCountPurchaseFeesTwice() {
        val result = GoldReturnCalculator.calculate(
            GoldReturnInput(
                grams = 10.0, purity = 0.9, unitPrice = 750.0,
                laborFee = 300.0, otherCost = 20.0, totalCostOverride = 8_000.0,
                rule = GoldRecoveryRule(perGramDeduction = 10.0, discountRate = 0.05, fixedFee = 20.0),
            ),
            referencePrice = 1_000.0,
        )!!
        assertEquals(8_000.0, result.totalCost, 1e-9)
        assertEquals(9.0, result.effectiveGrams, 1e-9)
        assertEquals(8_444.5, result.proceeds!!, 1e-9)
        assertEquals(444.5, result.profit!!, 1e-9)
        assertEquals(948.0116959064327, result.breakEvenPrice, 1e-9)
    }

    @Test
    fun missingQuotePreservesCostAndBreakEvenWithoutFabricatingValuation() {
        val result = GoldReturnCalculator.calculate(GoldReturnInput(5.0, 1.0, 800.0), null)!!
        assertEquals(4_000.0, result.totalCost, 0.0)
        assertEquals(800.0, result.breakEvenPrice, 0.0)
        assertNull(result.proceeds)
        assertNull(result.profit)
    }

    @Test
    fun portfolioBreakEvenAccountsForCashFloorPerRecord() {
        val lowCost = GoldReturnInput(1.0, 1.0, 100.0)
        val highCost = GoldReturnInput(1.0, 1.0, 300.0, rule = GoldRecoveryRule(perGramDeduction = 500.0))
        val portfolio = GoldReturnCalculator.aggregate(listOf(lowCost, highCost), 300.0)!!
        assertEquals(400.0, portfolio.breakEvenPrice!!, 1e-8)
        assertEquals(-100.0, portfolio.profit!!, 1e-8)
    }

    @Test
    fun partialSaleConservesPurchaseWeightAndCashCost() {
        val original = holding()
        val soldAt = purchaseDate.plusSeconds(3600)
        val (remaining, sold) = HoldingDisposal.apply(
            original, 4.0, HoldingDisposition.Sold, 3_800.0, soldAt,
            now = soldAt, splitId = disposalId,
        )!!
        assertEquals(6.0, remaining.input.grams, 0.0)
        assertEquals(4.0, sold.input.grams, 0.0)
        assertEquals(4_800.0, remaining.input.totalCost, 0.0)
        assertEquals(3_200.0, sold.input.totalCost, 0.0)
        assertEquals(180.0, remaining.input.laborFee, 0.0)
        assertEquals(120.0, sold.input.laborFee, 0.0)
        assertEquals(purchaseId, remaining.id)
        assertEquals(purchaseId, sold.purchaseId)
        assertEquals(purchaseDate, sold.timestamp)
        assertEquals(soldAt, sold.disposedAt)
        assertEquals(3_800.0, sold.disposalAmount, 0.0)
    }

    @Test
    fun calendarGroupsSplitPurchaseAndSaleOnTheCorrectLocalDates() {
        val soldAt = Instant.parse("2026-11-20T17:00:00Z")
        val records = HoldingDisposal.apply(
            holding(), 4.0, HoldingDisposition.Sold, 3_800.0, soldAt,
            now = soldAt, splitId = disposalId,
        )!!
        val days = HoldingCalendar.events(records, ZoneId.of("Asia/Shanghai"))
        assertEquals(2, days.size)
        val purchase = days.single { it.date == LocalDate.of(2026, 11, 20) }
        assertEquals(HoldingEventKind.Purchase, purchase.kind)
        assertEquals(10.0, purchase.grams, 0.0)
        assertEquals(8_000.0, purchase.amount, 0.0)
        val sale = days.single { it.date == LocalDate.of(2026, 11, 21) }
        assertEquals(HoldingEventKind.Sale, sale.kind)
        assertEquals(3_800.0, sale.amount, 0.0)
    }

    @Test
    fun rejectsDisposalOutsideThePurchaseAndPresentTimeBounds() {
        assertNull(
            HoldingDisposal.apply(
                holding(), 2.0, HoldingDisposition.Gift, 0.0, purchaseDate.minusSeconds(1),
                now = purchaseDate, splitId = disposalId,
            )
        )
        val gift = HoldingDisposal.apply(
            holding(), 10.0, HoldingDisposition.Gift, 3_000.0, purchaseDate,
            now = purchaseDate, splitId = disposalId,
        )
        assertNotNull(gift)
        assertTrue(gift!!.single().disposalAmount == 0.0)
    }

    @Test
    fun quickHoldingDraftAppliesPerGramLaborAndKeepsActualCashTotal() {
        val draft = HoldingDraft()
            .selectAssetType(HoldingAssetType.Jewelry)
            .copy(grams = "30", unitPrice = "780", useCashTotal = true, cashTotal = "25400")
        val input = draft.input()!!
        assertEquals(0.999, input.purity, 1e-9)
        assertEquals(1500.0, input.laborFee, 0.0)
        assertEquals(25_400.0, input.totalCost, 0.0)
        assertNull(draft.copy(discountPercent = "100").input())
    }

    @Test
    fun linkedPriceFieldsUseActualCashUntilUserEditsUnitPrice() {
        val draft = HoldingDraft(grams = "5", unitPrice = "750", labor = "10")
        assertEquals(3_800.0, draft.input()!!.totalCost, 0.0)
        val withActualCash = draft.enterCashTotal("3900")
        assertEquals(3_900.0, withActualCash.input()!!.totalCost, 0.0)
        assertEquals(3_800.0, withActualCash.enterCashTotal("").input()!!.totalCost, 0.0)
        assertEquals(3_650.0, withActualCash.enterUnitPrice("720").input()!!.totalCost, 0.0)
    }

    @Test
    fun editingExistingRecordKeepsItsSavedPurityAndLaborWhenChangingAssetType() {
        val draft = HoldingDraft.from(holding())
        val edited = draft.selectAssetType(HoldingAssetType.Bean, applyDefaults = false)
        assertEquals(HoldingAssetType.Bean, edited.assetType)
        assertEquals(draft.purityPercent, edited.purityPercent)
        assertEquals(draft.labor, edited.labor)
        assertEquals(8_000.0, edited.input()!!.totalCost, 0.0)
    }

    private fun holding() = HoldingRecord(
        id = purchaseId,
        input = GoldReturnInput(10.0, 0.9, 750.0, laborFee = 300.0, totalCostOverride = 8_000.0),
        timestamp = purchaseDate,
        createdAt = purchaseDate,
        bookName = "家庭",
    )
}
