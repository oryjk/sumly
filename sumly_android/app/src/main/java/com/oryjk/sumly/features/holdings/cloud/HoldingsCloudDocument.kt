package com.oryjk.sumly.features.holdings.cloud

import com.oryjk.sumly.features.holdings.DEFAULT_HOLDING_BOOK
import com.oryjk.sumly.features.holdings.HoldingDisposition
import com.oryjk.sumly.features.holdings.HoldingRecord
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.util.UUID

/** Keep the wire fields that the Android record editor does not model. */
internal data class HoldingCloudRecord(
    val holding: HoldingRecord,
    val timestampMillis: Double,
    val createdAtMillis: Double,
    val disposedAtMillis: Double?,
    val assetType: String,
) {
    val id: UUID get() = holding.id

    fun validate(books: Set<String>) {
        val input = holding.input
        require(holding.bookName in books && input.grams.isFinite() && input.grams > 0)
        require(input.unitPrice.isNonnegative() && (input.unitPrice > 0 || (input.totalCostOverride ?: 0.0) > 0))
        require(timestampMillis.isWireDate() && createdAtMillis.isWireDate())
        require(disposedAtMillis != null || holding.disposition == HoldingDisposition.Holding)
        require(disposedAtMillis == null || (disposedAtMillis.isWireDate() && disposedAtMillis >= timestampMillis))
        require(holding.note.isWireText(2_000))
        require(listOf(holding.brand, holding.purchaseChannel, holding.counterparty, assetType).all { it.isWireText(200) })
        require(input.totalCostOverride?.isNonnegative() != false)
        require(input.purity.isFinite() && input.purity > 0 && input.purity <= 1 && input.rule.isValid)
        require(holding.disposalAmount.isNonnegative() && input.otherCost.isNonnegative() && input.laborFee.isNonnegative())
        val alerts = holding.alerts
        require(alerts.size <= 4 && alerts.distinctBy { it.id }.size == alerts.size && alerts.all { it.isValid })
    }

    companion object {
        fun fromHolding(
            holding: HoldingRecord,
            previous: HoldingCloudRecord? = null,
            purchase: HoldingCloudRecord? = null,
        ): HoldingCloudRecord {
            val original = previous ?: purchase
            // An existing wire date can be more precise than Instant. Keep its exact
            // value when the editor left the projected date unchanged.
            val timestamp = original?.timestampMillis?.takeIf { original.holding.timestamp == holding.timestamp }
                ?: holding.timestamp.toWireMillis()
            val createdAt = original?.createdAtMillis?.takeIf { original.holding.createdAt == holding.createdAt }
                ?: holding.createdAt.toWireMillis()
            val disposedAt = previous?.disposedAtMillis?.takeIf { previous.holding.disposedAt == holding.disposedAt }
                ?: holding.disposedAt?.toWireMillis()
            val asset = original?.assetType?.takeIf { original.holding.assetType == holding.assetType }
                ?: holding.assetType.title
            val projected = holding.copy(
                timestamp = timestamp.toWireInstant(),
                createdAt = createdAt.toWireInstant(),
                disposedAt = disposedAt?.toWireInstant(),
                alerts = holding.alerts.sortedBy { it.id.toString() },
            )
            return HoldingCloudRecord(projected, timestamp, createdAt, disposedAt, asset)
        }
    }
}

internal data class HoldingsCloudDocument(
    val books: List<String>,
    val records: List<HoldingCloudRecord>,
) {
    fun normalized(): HoldingsCloudDocument = copy(
        books = (books + DEFAULT_HOLDING_BOOK).distinct().sorted(),
        records = records.sortedBy { it.id.toString() },
    )

    fun validate(): HoldingsCloudDocument {
        val names = books.toSet()
        require(books.size in 1..100 && records.size <= 1_000 && names.size == books.size)
        require(books.all { it.isNotBlank() && it.isWireText(100) })
        require(records.distinctBy { it.id }.size == records.size)
        records.forEach { it.validate(names) }
        return this
    }

    companion object {
        val Empty = HoldingsCloudDocument(listOf(DEFAULT_HOLDING_BOOK), emptyList())
    }
}

internal data class HoldingsCloudSnapshot(val revision: Long, val document: HoldingsCloudDocument) {
    fun validate(): HoldingsCloudSnapshot {
        require(revision >= 0 && revision < Long.MAX_VALUE)
        document.validate()
        return this
    }

    companion object {
        val Empty = HoldingsCloudSnapshot(0, HoldingsCloudDocument.Empty)
    }
}

internal fun Double.isWireDate() = isFinite() && this in -62_135_596_800_000.0..253_402_300_799_999.0

internal fun Double.toWireInstant(): Instant {
    require(isWireDate())
    val decimalMillis = BigDecimal.valueOf(this)
    val millis = decimalMillis.setScale(0, RoundingMode.FLOOR).longValueExact()
    val nanosAfterMilli = decimalMillis.subtract(BigDecimal.valueOf(millis))
        .movePointRight(6).setScale(0, RoundingMode.HALF_EVEN).longValueExact()
    return Instant.ofEpochMilli(millis).plusNanos(nanosAfterMilli)
}

private fun Instant.toWireMillis(): Double = epochSecond * 1_000.0 + nano / 1_000_000.0
private fun Double.isNonnegative(): Boolean = isFinite() && this >= 0
private fun String.isWireText(max: Int): Boolean = codePointCount(0, length) <= max && '\u0000' !in this
