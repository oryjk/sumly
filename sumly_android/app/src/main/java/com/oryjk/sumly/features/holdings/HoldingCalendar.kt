package com.oryjk.sumly.features.holdings

import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

enum class HoldingEventKind(val title: String) { Purchase("购入"), Sale("卖出"), Gift("赠出") }

data class HoldingEvent(
    val id: UUID,
    val date: LocalDate,
    val kind: HoldingEventKind,
    val title: String,
    val bookName: String,
    val grams: Double,
    val amount: Double,
)

object HoldingCalendar {
    fun events(records: List<HoldingRecord>, zone: ZoneId): List<HoldingEvent> {
        val purchases = records.groupBy { it.purchaseId ?: it.id }.map { (purchaseId, pieces) ->
            val sample = pieces.firstOrNull { it.id == purchaseId } ?: pieces.first()
            HoldingEvent(
                purchaseId, sample.timestamp.atZone(zone).toLocalDate(), HoldingEventKind.Purchase,
                sample.displayName, sample.bookName, pieces.sumOf { it.input.grams },
                pieces.sumOf { it.input.totalCost },
            )
        }
        val disposals = records.mapNotNull { record ->
            val date = record.disposedAt?.atZone(zone)?.toLocalDate() ?: return@mapNotNull null
            val kind = when (record.disposition) {
                HoldingDisposition.Holding -> return@mapNotNull null
                HoldingDisposition.Sold -> HoldingEventKind.Sale
                HoldingDisposition.Gift -> HoldingEventKind.Gift
            }
            HoldingEvent(
                record.id, date, kind, record.displayName, record.bookName, record.input.grams,
                record.disposalAmount,
            )
        }
        return (purchases + disposals).sortedWith(compareByDescending<HoldingEvent> { it.date }.thenBy { it.kind })
    }
}
