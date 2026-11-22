package com.oryjk.sumly.features.holdings.alerts

import com.oryjk.sumly.features.market.MarketBasis
import java.util.UUID
import org.json.JSONObject

internal object HoldingAlertJson {
    private val fields = setOf("id", "kind", "threshold", "enabled", "basis")

    fun decode(value: JSONObject): HoldingAlert {
        require(value.keys().asSequence().all { it in fields })
        val text = value.get("id") as String
        val id = UUID.fromString(text)
        require(id.toString().equals(text, ignoreCase = true))
        return HoldingAlert(
            id = id,
            kind = HoldingAlertKind.entries.first { it.key == value.get("kind") },
            threshold = (value.get("threshold") as Number).toDouble(),
            enabled = value.get("enabled") as Boolean,
            basis = when (value.get("basis")) {
                "domestic" -> MarketBasis.Domestic
                "international" -> MarketBasis.International
                else -> error("Invalid holding alert basis")
            },
        ).also { require(it.isValid) }
    }

    fun encode(alert: HoldingAlert) = JSONObject()
        .put("id", alert.id.toString())
        .put("kind", alert.kind.key)
        .put("threshold", alert.threshold)
        .put("enabled", alert.enabled)
        .put("basis", if (alert.basis == MarketBasis.Domestic) "domestic" else "international")
}
