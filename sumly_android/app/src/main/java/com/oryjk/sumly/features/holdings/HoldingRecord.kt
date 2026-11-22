package com.oryjk.sumly.features.holdings

import com.oryjk.sumly.features.holdings.alerts.HoldingAlert
import java.time.Instant
import java.util.UUID

const val DEFAULT_HOLDING_BOOK = "默认账本"

enum class HoldingAssetType(val title: String, val purityPercent: String, val laborPerGram: String) {
    Bean("金豆", "99.99", "10"),
    Bar("金条", "99.99", "10"),
    Jewelry("金饰", "99.9", "50"),
    Accumulation("积存金", "99.99", "0"),
    Other("其他", "99.99", ""),
}

enum class HoldingDisposition(val key: String, val title: String) {
    Holding("holding", "持有"),
    Sold("sold", "卖出"),
    Gift("gift", "赠出"),
}

data class HoldingRecord(
    val id: UUID = UUID.randomUUID(),
    val input: GoldReturnInput,
    val timestamp: Instant,
    val createdAt: Instant = Instant.now(),
    val bookName: String = DEFAULT_HOLDING_BOOK,
    val assetType: HoldingAssetType = HoldingAssetType.Other,
    val brand: String = "",
    val note: String = "",
    val purchaseChannel: String = "",
    val counterparty: String = "",
    val disposition: HoldingDisposition = HoldingDisposition.Holding,
    val disposedAt: Instant? = null,
    val disposalAmount: Double = 0.0,
    val purchaseId: UUID? = null,
    val alerts: List<HoldingAlert> = emptyList(),
) {
    val displayName: String
        get() = brand.trim().ifEmpty { if (assetType == HoldingAssetType.Other) "黄金记录" else assetType.title }
}

object HoldingDisposal {
    fun apply(
        record: HoldingRecord,
        grams: Double,
        kind: HoldingDisposition,
        proceeds: Double,
        date: Instant,
        now: Instant,
        counterparty: String? = null,
        splitId: UUID = UUID.randomUUID(),
    ): List<HoldingRecord>? {
        if (record.disposition != HoldingDisposition.Holding || kind == HoldingDisposition.Holding ||
            !grams.isFinite() || grams <= 0.0 || grams > record.input.grams ||
            !proceeds.isFinite() || proceeds < 0.0 || date < record.timestamp || date > now
        ) return null
        val disposed = record.copy(
            disposition = kind,
            disposedAt = date,
            disposalAmount = if (kind == HoldingDisposition.Gift) 0.0 else proceeds,
            counterparty = counterparty ?: record.counterparty,
            alerts = emptyList(),
        )
        if (grams == record.input.grams) return listOf(disposed)

        val fraction = grams / record.input.grams
        val soldInput = record.input.copy(
            grams = grams,
            laborFee = record.input.laborFee * fraction,
            otherCost = record.input.otherCost * fraction,
            totalCostOverride = record.input.totalCostOverride?.times(fraction),
        )
        val remainingInput = record.input.copy(
            grams = record.input.grams - grams,
            laborFee = record.input.laborFee - soldInput.laborFee,
            otherCost = record.input.otherCost - soldInput.otherCost,
            totalCostOverride = record.input.totalCostOverride?.minus(soldInput.totalCostOverride ?: 0.0),
        )
        return listOf(
            record.copy(input = remainingInput),
            disposed.copy(id = splitId, input = soldInput, purchaseId = record.purchaseId ?: record.id),
        )
    }
}
