package com.oryjk.sumly.features.holdings

import java.math.BigDecimal
import java.time.Instant

data class HoldingDraft(
    val timestamp: Instant = Instant.now(),
    val assetType: HoldingAssetType = HoldingAssetType.Bar,
    val grams: String = "",
    val unitPrice: String = "",
    val cashTotal: String = "",
    val useCashTotal: Boolean = false,
    val purityPercent: String = "99.99",
    val labor: String = "",
    val laborPerGram: Boolean = true,
    val extraFee: String = "",
    val deduction: String = "",
    val discountPercent: String = "",
    val fixedFee: String = "",
    val brand: String = "",
    val channel: String = "",
    val note: String = "",
    val bookName: String = DEFAULT_HOLDING_BOOK,
) {
    fun selectAssetType(newType: HoldingAssetType, applyDefaults: Boolean = true): HoldingDraft =
        if (applyDefaults) {
            copy(
                assetType = newType, purityPercent = newType.purityPercent, labor = newType.laborPerGram,
                laborPerGram = true,
            )
        } else copy(assetType = newType)

    fun enterUnitPrice(value: String): HoldingDraft = copy(unitPrice = value, cashTotal = "", useCashTotal = false)

    fun enterCashTotal(value: String): HoldingDraft = copy(cashTotal = value, useCashTotal = value.isNotBlank())

    fun input(): GoldReturnInput? {
        val weight = parseNumber(grams)?.takeIf { it > 0.0 && it <= 1_000_000 } ?: return null
        val charge = parseNumber(labor, optional = true) ?: return null
        val laborTotal = if (laborPerGram) charge * weight else charge
        val other = parseNumber(extraFee, optional = true) ?: return null
        val purity = parseNumber(purityPercent)?.takeIf { it > 0.0 && it <= 100 } ?: return null
        val discount = parseNumber(discountPercent, optional = true)?.takeIf { it < 100 } ?: return null
        val perGramDeduction = parseNumber(deduction, optional = true) ?: return null
        val recoveryFixedFee = parseNumber(fixedFee, optional = true) ?: return null
        val override = if (useCashTotal) parseNumber(cashTotal)?.takeIf { it > 0.0 } ?: return null else null
        val price = if (override != null) {
            parseNumber(unitPrice) ?: ((override - laborTotal - other) / weight).coerceAtLeast(0.0)
        } else {
            parseNumber(unitPrice)?.takeIf { it > 0.0 && it <= 1_000_000 } ?: return null
        }
        return GoldReturnInput(
            grams = weight, purity = purity / 100, unitPrice = price, laborFee = laborTotal,
            otherCost = other, totalCostOverride = override,
            rule = GoldRecoveryRule(perGramDeduction, discount / 100, recoveryFixedFee),
        ).takeIf { it.isValid }
    }

    companion object {
        fun from(record: HoldingRecord): HoldingDraft {
            val input = record.input
            return HoldingDraft(
                timestamp = record.timestamp,
                assetType = record.assetType,
                grams = holdingNumber(input.grams),
                unitPrice = holdingNumber(input.unitPrice),
                cashTotal = input.totalCostOverride?.let(::holdingNumber).orEmpty(),
                useCashTotal = input.totalCostOverride != null,
                purityPercent = holdingNumber(input.purity * 100),
                labor = holdingNumber(input.laborFee),
                laborPerGram = false,
                extraFee = holdingNumber(input.otherCost),
                deduction = holdingNumber(input.rule.perGramDeduction),
                discountPercent = holdingNumber(input.rule.discountRate * 100),
                fixedFee = holdingNumber(input.rule.fixedFee),
                brand = record.brand,
                channel = record.purchaseChannel,
                note = record.note,
                bookName = record.bookName,
            )
        }

        private fun parseNumber(text: String, optional: Boolean = false): Double? {
            val normalized = text.trim()
            if (normalized.isEmpty() && optional) return 0.0
            return normalized.toDoubleOrNull()?.takeIf { it >= 0.0 && it <= 1_000_000_000 }
        }
    }
}

internal fun holdingNumber(value: Double): String =
    BigDecimal.valueOf(value).stripTrailingZeros().toPlainString()
