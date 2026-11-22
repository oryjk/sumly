package com.oryjk.sumly.features.holdings

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HoldingMarketOverlayTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val purchaseTime = Instant.parse("2026-11-19T18:07:40Z")

    @Test
    fun weightsSameDayPurchaseMarkersUsingTheActualCashOutlayPerGrossGram() {
        val bar = holding(
            GoldReturnInput(grams = 10.0, purity = 0.95, unitPrice = 700.0, laborFee = 200.0),
        )
        val jewelry = holding(
            GoldReturnInput(5.0, 0.9, 800.0, laborFee = 500.0, totalCostOverride = 4_800.0),
            date = purchaseTime.plusSeconds(6 * 3600),
        )
        val overlay = HoldingMarketOverlay.from(snapshot(bar, jewelry), zone)!!
        val marker = overlay.markers.single()

        assertEquals(LocalDate.of(2026, 11, 20), marker.id)
        assertEquals(Instant.parse("2026-11-20T04:00:00Z"), marker.timestamp)
        assertEquals(800.0, marker.cnyPerGram, 1e-9)
        assertEquals(2, marker.count)
        assertEquals(listOf(720.0, 960.0), marker.items.map { it.cnyPerGram })
        assertEquals(857.1428571428571, overlay.breakEven!!, 1e-9)
    }

    @Test
    fun valuationExcludesSalesAndOtherLedgersAndMergesTheActivePurchaseFamily() {
        val original = holding(
            GoldReturnInput(4.0, 1.0, 600.0, rule = GoldRecoveryRule(perGramDeduction = 10.0)),
        )
        val samePurchase = holding(GoldReturnInput(2.0, 1.0, 660.0)).copy(purchaseId = original.id)
        val sold = holding(GoldReturnInput(6.0, 1.0, 400.0)).copy(
            purchaseId = original.id,
            disposition = HoldingDisposition.Sold,
        )
        val otherBook = holding(GoldReturnInput(20.0, 1.0, 900.0), book = "其他账本")
        val overlay = HoldingMarketOverlay.from(snapshot(original, samePurchase, sold, otherBook, original), zone)!!
        val marker = overlay.markers.single()

        assertEquals(1, marker.count)
        assertEquals(original.id, marker.items.single().id)
        assertEquals(6.0, marker.totalGrams, 0.0)
        assertEquals(620.0, marker.cnyPerGram, 0.0)
        assertEquals(626.6666666666666, overlay.breakEven!!, 1e-9)
    }

    @Test
    fun windowClipsMarkersButKeepsBreakEvenForEarlierHoldings() {
        val old = holding(GoldReturnInput(20.0, 1.0, 500.0), date = purchaseTime.minusSeconds(86400 * 100L))
        val new = holding(GoldReturnInput(20.0, 1.0, 750.0))
        val window = purchaseTime..purchaseTime.plusSeconds(86400)
        val overlay = HoldingMarketOverlay.from(snapshot(new, old), zone, window)!!

        assertEquals(750.0, overlay.markers.single().cnyPerGram, 0.0)
        assertEquals(625.0, overlay.breakEven!!, 1e-9)
    }

    @Test
    fun privateModeAndEmptyHoldingsDoNotExposeTrackingValues() {
        val source = snapshot(holding(GoldReturnInput(20.0, 1.0, 750.0)))
        assertNull(HoldingMarketOverlay.from(source.copy(amountsHidden = true), zone))
        assertNull(HoldingMarketOverlay.from(snapshot(), zone))
    }

    private fun holding(
        input: GoldReturnInput, date: Instant = purchaseTime, book: String = "旅行",
    ): HoldingRecord = HoldingRecord(
        id = UUID.randomUUID(), input = input, timestamp = date, createdAt = date, bookName = book,
    )

    private fun snapshot(vararg records: HoldingRecord): HoldingsSnapshot = HoldingsSnapshot(
        books = listOf(DEFAULT_HOLDING_BOOK, "旅行", "其他账本"), records = records.toList(), currentBook = "旅行",
    )
}
