package com.oryjk.sumly.features.holdings

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

data class HoldingMarketPurchase(
    val id: UUID,
    val timestamp: Instant,
    val displayName: String,
    val assetType: HoldingAssetType,
    val grams: Double,
    val totalCost: Double,
    val cnyPerGram: Double,
    val unitPrice: Double,
    val laborFee: Double,
    val note: String,
)

data class HoldingMarketMarker(
    val id: LocalDate,
    val timestamp: Instant,
    val cnyPerGram: Double,
    val totalGrams: Double,
    val items: List<HoldingMarketPurchase>,
) {
    val count: Int get() = items.size
}

data class HoldingMarketOverlay(
    val breakEven: Double?,
    val markers: List<HoldingMarketMarker>,
) {
    companion object {
        fun from(
            snapshot: HoldingsSnapshot,
            zone: ZoneId = ZoneId.systemDefault(),
            window: ClosedRange<Instant>? = null,
        ): HoldingMarketOverlay? {
            // A marker's vertical position also reveals cost, even without a text label.
            if (snapshot.amountsHidden) return null
            val held = snapshot.records.filter {
                it.bookName == snapshot.currentBook && it.disposition == HoldingDisposition.Holding && it.input.isValid
            }.distinctBy { it.id }
            if (held.isEmpty()) return null

            val breakEven = GoldReturnCalculator.aggregate(held.map { it.input }, null)?.breakEvenPrice
            val purchases = held.groupBy { it.purchaseId ?: it.id }.mapNotNull { (id, pieces) ->
                makePurchase(id, pieces)
            }
            val markers = purchases.groupBy { it.timestamp.atZone(zone).toLocalDate() }
                .mapNotNull { (day, items) ->
                    val noon = day.atTime(LocalTime.NOON).atZone(zone).toInstant()
                    if (window != null && noon !in window) return@mapNotNull null
                    val grams = items.sumOf { it.grams }
                    val averageCost = items.sumOf { it.totalCost } / grams
                    if (!grams.isFinite() || !averageCost.isFinite()) return@mapNotNull null
                    val sortedItems = items.sortedWith(
                        compareBy<HoldingMarketPurchase> { it.timestamp }
                            .thenByDescending { it.cnyPerGram }
                            .thenBy { it.displayName }
                            .thenBy { it.id },
                    )
                    HoldingMarketMarker(day, noon, averageCost, grams, sortedItems)
                }
                .sortedBy { it.timestamp }
            return HoldingMarketOverlay(breakEven, markers).takeIf { it.breakEven != null || it.markers.isNotEmpty() }
        }

        private fun makePurchase(id: UUID, pieces: List<HoldingRecord>): HoldingMarketPurchase? {
            // Partial disposals preserve their family ID. Only amounts still held contribute here.
            val original = pieces.firstOrNull { it.id == id }
                ?: pieces.minWith(compareBy<HoldingRecord> { it.timestamp }.thenBy { it.id })
            val grams = pieces.sumOf { it.input.grams }
            val totalCost = pieces.sumOf { it.input.totalCost }
            val cnyPerGram = totalCost / grams
            val unitPrice = pieces.sumOf { it.input.unitPrice * it.input.grams } / grams
            val laborFee = pieces.sumOf { it.input.laborFee }
            if (!listOf(grams, totalCost, cnyPerGram, unitPrice, laborFee).all(Double::isFinite)) return null
            return HoldingMarketPurchase(
                id, original.timestamp, original.displayName, original.assetType, grams, totalCost,
                cnyPerGram, unitPrice, laborFee, original.note,
            )
        }
    }
}
