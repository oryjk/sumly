package com.oryjk.sumly.features.holdings.cloud

import com.oryjk.sumly.features.holdings.GoldRecoveryRule
import com.oryjk.sumly.features.holdings.GoldReturnInput
import com.oryjk.sumly.features.holdings.HoldingAssetType
import com.oryjk.sumly.features.holdings.HoldingDisposition
import com.oryjk.sumly.features.holdings.HoldingRecord
import com.oryjk.sumly.features.holdings.alerts.HoldingAlertJson
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal const val HoldingsCloudMaxBytes = 4 * 1024 * 1024

internal object HoldingCloudWire {
    private val documentFields = setOf("schemaVersion", "books", "records")
    private val recordFields = setOf(
        "id", "grams", "unitPriceCNY", "timestamp", "note", "createdAt", "brand", "bookName", "disposition",
        "disposedAt", "disposalAmount", "purchaseID", "extraFee", "purchaseChannel", "counterparty", "assetType",
        "purity", "laborFee", "purchaseTotalOverride", "recoveryDeduction", "recoveryDiscount", "recoveryFixedFee", "alerts",
    )

    fun decodeSnapshot(json: JSONObject): HoldingsCloudSnapshot = HoldingsCloudSnapshot(
        revision = json.exactLong("revision"), document = decodeDocument(json.getJSONObject("document")),
    ).validate()

    fun encodeSnapshot(snapshot: HoldingsCloudSnapshot): JSONObject = JSONObject()
        .put("revision", snapshot.revision)
        .put("document", encodeDocument(snapshot.document))

    fun decodeDocument(json: JSONObject): HoldingsCloudDocument {
        json.rejectUnknownFields(documentFields)
        require(json.exactLong("schemaVersion") == 1L)
        val document = HoldingsCloudDocument(
            books = json.getJSONArray("books").values { get(it) as String },
            records = json.getJSONArray("records").values { decodeRecord(getJSONObject(it)) },
        )
        return document.validate().normalized().validate()
    }

    fun encodeDocument(document: HoldingsCloudDocument): JSONObject = JSONObject()
        .put("schemaVersion", 1)
        .put("books", JSONArray(document.books))
        .put("records", JSONArray(document.records.map(::encodeRecord)))

    private fun decodeRecord(json: JSONObject): HoldingCloudRecord {
        json.rejectUnknownFields(recordFields)
        val timestamp = json.wireDouble("timestamp")
        val createdAt = json.wireDouble("createdAt")
        val disposedAt = json.optional("disposedAt") { json.wireDouble(it) }
        val assetType = json.wireString("assetType")
        val disposition = json.wireString("disposition")
        val holding = HoldingRecord(
            id = json.uuid("id"),
            input = GoldReturnInput(
                grams = json.wireDouble("grams"),
                purity = json.wireDouble("purity"),
                unitPrice = json.wireDouble("unitPriceCNY"),
                laborFee = json.wireDouble("laborFee"),
                otherCost = json.wireDouble("extraFee"),
                totalCostOverride = json.optional("purchaseTotalOverride") { json.wireDouble(it) },
                rule = GoldRecoveryRule(json.wireDouble("recoveryDeduction"), json.wireDouble("recoveryDiscount"), json.wireDouble("recoveryFixedFee")),
            ),
            timestamp = timestamp.toWireInstant(),
            createdAt = createdAt.toWireInstant(),
            bookName = json.wireString("bookName"),
            assetType = HoldingAssetType.entries.find { it.title == assetType } ?: HoldingAssetType.Other,
            brand = json.wireString("brand"),
            note = json.wireString("note"),
            purchaseChannel = json.wireString("purchaseChannel"),
            counterparty = json.wireString("counterparty"),
            disposition = HoldingDisposition.entries.first { it.key == disposition },
            disposedAt = disposedAt?.toWireInstant(),
            disposalAmount = json.wireDouble("disposalAmount"),
            purchaseId = json.optional("purchaseID") { json.uuid(it) },
            alerts = json.getJSONArray("alerts").values { HoldingAlertJson.decode(getJSONObject(it)) }
                .sortedBy { it.id.toString() },
        )
        return HoldingCloudRecord(holding, timestamp, createdAt, disposedAt, assetType)
    }

    private fun encodeRecord(record: HoldingCloudRecord): JSONObject = with(record.holding) {
        JSONObject().apply {
            put("id", id.toString())
            put("grams", input.grams)
            put("unitPriceCNY", input.unitPrice)
            put("timestamp", record.timestampMillis)
            put("note", note)
            put("createdAt", record.createdAtMillis)
            put("brand", brand)
            put("bookName", bookName)
            put("disposition", disposition.key)
            record.disposedAtMillis?.let { put("disposedAt", it) }
            put("disposalAmount", disposalAmount)
            purchaseId?.let { put("purchaseID", it.toString()) }
            put("extraFee", input.otherCost)
            put("purchaseChannel", purchaseChannel)
            put("counterparty", counterparty)
            put("assetType", record.assetType)
            put("purity", input.purity)
            put("laborFee", input.laborFee)
            input.totalCostOverride?.let { put("purchaseTotalOverride", it) }
            put("recoveryDeduction", input.rule.perGramDeduction)
            put("recoveryDiscount", input.rule.discountRate)
            put("recoveryFixedFee", input.rule.fixedFee)
            put("alerts", JSONArray(alerts.map(HoldingAlertJson::encode)))
        }
    }

    private fun JSONObject.exactLong(key: String): Long {
        val value = get(key)
        require(value is Number)
        return requireNotNull(value.toString().toLongOrNull())
    }

    private fun JSONObject.wireDouble(key: String): Double = (get(key) as Number).toDouble()

    private fun JSONObject.wireString(key: String): String = get(key) as String

    private fun JSONObject.uuid(key: String): UUID {
        val text = wireString(key)
        val uuid = UUID.fromString(text)
        require(uuid.toString().equals(text, ignoreCase = true))
        return uuid
    }

    private fun <T> JSONObject.optional(key: String, read: (String) -> T): T? = if (isNull(key)) null else read(key)

    // A full-document PUT cannot safely round-trip fields this app version does not understand.
    private fun JSONObject.rejectUnknownFields(known: Set<String>) = require(keys().asSequence().all { it in known })

    private fun <T> JSONArray.values(read: JSONArray.(Int) -> T): List<T> = List(length()) { read(it) }
}
