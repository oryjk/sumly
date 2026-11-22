package com.oryjk.sumly.features.holdings

import java.time.Instant

internal data class HoldingReceiptSnapshot(
    val assetType: HoldingAssetType,
    val addedGrams: Double,
    val totalCost: Double,
    val timestamp: Instant,
    val purchaseSequence: Int,
    val totalBookGrams: Double,
    val bookName: String,
    val nextMilestone: String?,
    val remainingGrams: Double,
    val progress: Float,
    val newMilestone: String?,
) {
    companion object {
        private val milestones = listOf(
            1.0 to "首克 1g",
            10.0 to "10g 初成",
            50.0 to "50g 筑底",
            100.0 to "100g 小金砖",
            500.0 to "500g 金库",
            1_000.0 to "1kg 典藏",
        )

        fun from(record: HoldingRecord, committed: HoldingsSnapshot): HoldingReceiptSnapshot {
            val purchases = committed.records.filter {
                it.id != record.id && it.bookName == record.bookName && it.disposition == HoldingDisposition.Holding
            }
            val previousGrams = purchases.sumOf { it.input.grams }
            val addedGrams = record.input.grams
            val total = previousGrams + addedGrams
            val next = milestones.firstOrNull { total < it.first }
            val unlocked = milestones.lastOrNull { (target, _) -> previousGrams < target && total >= target }
            return HoldingReceiptSnapshot(
                assetType = record.assetType,
                addedGrams = addedGrams,
                totalCost = record.input.totalCost,
                timestamp = record.timestamp,
                purchaseSequence = purchases.size + 1,
                totalBookGrams = total,
                bookName = record.bookName,
                nextMilestone = next?.second,
                remainingGrams = next?.first?.minus(total) ?: 0.0,
                progress = next?.let { (total / it.first).coerceIn(0.0, 1.0).toFloat() } ?: 1.0f,
                newMilestone = unlocked?.second,
            )
        }
    }
}
