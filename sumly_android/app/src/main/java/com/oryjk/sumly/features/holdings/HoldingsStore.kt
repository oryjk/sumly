package com.oryjk.sumly.features.holdings

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.oryjk.sumly.features.holdings.alerts.HoldingAlertJson
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

data class HoldingsSnapshot(
    val books: List<String> = listOf(DEFAULT_HOLDING_BOOK),
    val records: List<HoldingRecord> = emptyList(),
    val amountsHidden: Boolean = false,
    val currentBook: String = DEFAULT_HOLDING_BOOK,
)

interface HoldingsStore {
    fun load(): HoldingsSnapshot
    fun saveRecords(records: List<HoldingRecord>): HoldingsSnapshot
    fun saveRecordsIfUnchanged(expected: HoldingRecord?, records: List<HoldingRecord>): HoldingsSnapshot = saveRecords(records)
    fun deleteRecord(id: UUID): HoldingsSnapshot
    fun deleteRecordIfUnchanged(expected: HoldingRecord): HoldingsSnapshot = deleteRecord(expected.id)
    fun createBook(name: String): HoldingsSnapshot
    fun setCurrentBook(name: String): HoldingsSnapshot
    fun setAmountsHidden(hidden: Boolean): HoldingsSnapshot
}

/** A separate database holds device-local guest records only. */
class SQLiteGuestHoldingsStore(context: Context) : HoldingsStore {
    private val helper = GuestHoldingsDatabase(context.applicationContext)

    override fun load(): HoldingsSnapshot = helper.readableDatabase.snapshot()

    override fun saveRecords(records: List<HoldingRecord>): HoldingsSnapshot = write {
        records.forEach { record ->
            insertBook(record.bookName)
            val values = ContentValues().apply {
                put("id", record.id.toString())
                put("book_name", record.bookName)
                put("timestamp", record.timestamp.toEpochMilli())
                put("payload", HoldingRecordJson.encode(record).toString())
            }
            check(insertWithOnConflict("holdings", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
        }
    }

    override fun deleteRecord(id: UUID): HoldingsSnapshot = write {
        delete("holdings", "id = ?", arrayOf(id.toString()))
    }

    override fun createBook(name: String): HoldingsSnapshot = write {
        insertBook(name)
        setPreference("current_book", name)
    }

    override fun setCurrentBook(name: String): HoldingsSnapshot = write {
        setPreference("current_book", name)
    }

    override fun setAmountsHidden(hidden: Boolean): HoldingsSnapshot = write {
        setPreference("amounts_hidden", if (hidden) "1" else "0")
    }

    private fun write(change: SQLiteDatabase.() -> Unit): HoldingsSnapshot {
        val database = helper.writableDatabase
        database.beginTransaction()
        try {
            database.change()
            val snapshot = database.snapshot()
            database.setTransactionSuccessful()
            return snapshot
        } finally {
            database.endTransaction()
        }
    }

    private fun SQLiteDatabase.insertBook(name: String) {
        execSQL("INSERT OR IGNORE INTO books(name) VALUES (?)", arrayOf(name))
    }

    private fun SQLiteDatabase.setPreference(name: String, value: String) {
        val values = ContentValues().apply {
            put("name", name)
            put("value", value)
        }
        check(insertWithOnConflict("preferences", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }

    private fun SQLiteDatabase.snapshot(): HoldingsSnapshot {
        val books = rawQuery("SELECT name FROM books ORDER BY name", null).use { rows ->
            buildList { while (rows.moveToNext()) add(rows.getString(0)) }
        }
        val records = rawQuery("SELECT payload FROM holdings ORDER BY timestamp DESC, id ASC", null).use { rows ->
            buildList {
                while (rows.moveToNext()) add(HoldingRecordJson.decode(JSONObject(rows.getString(0))))
            }
        }
        val preferences = rawQuery("SELECT name, value FROM preferences", null).use { rows ->
            buildMap { while (rows.moveToNext()) put(rows.getString(0), rows.getString(1)) }
        }
        return HoldingsSnapshot(
            books = listOf(DEFAULT_HOLDING_BOOK) + books.filterNot { it == DEFAULT_HOLDING_BOOK },
            records = records,
            amountsHidden = preferences["amounts_hidden"] == "1",
            currentBook = preferences["current_book"]?.takeIf { it in books } ?: DEFAULT_HOLDING_BOOK,
        )
    }

    private class GuestHoldingsDatabase(context: Context) :
        SQLiteOpenHelper(context, "sumly-guest-holdings.db", null, 1) {
        override fun onConfigure(db: SQLiteDatabase) {
            db.setForeignKeyConstraintsEnabled(true)
        }

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE books (name TEXT PRIMARY KEY NOT NULL)")
            db.execSQL(
                """CREATE TABLE holdings (
                    id TEXT PRIMARY KEY NOT NULL,
                    book_name TEXT NOT NULL REFERENCES books(name),
                    timestamp INTEGER NOT NULL,
                    payload TEXT NOT NULL
                )""".trimIndent()
            )
            db.execSQL("CREATE INDEX holdings_timestamp ON holdings(timestamp DESC)")
            db.execSQL("CREATE TABLE preferences (name TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
            db.execSQL("INSERT INTO books(name) VALUES (?)", arrayOf(DEFAULT_HOLDING_BOOK))
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            error("Missing guest holdings database migration from $oldVersion to $newVersion")
        }
    }
}

private object HoldingRecordJson {
    fun encode(record: HoldingRecord) = JSONObject().apply {
        put("id", record.id.toString())
        put("grams", record.input.grams)
        put("unitPriceCNY", record.input.unitPrice)
        put("timestamp", record.timestamp.toEpochMilli())
        put("createdAt", record.createdAt.toEpochMilli())
        put("bookName", record.bookName)
        put("assetType", record.assetType.title)
        put("brand", record.brand)
        put("note", record.note)
        put("purchaseChannel", record.purchaseChannel)
        put("counterparty", record.counterparty)
        put("disposition", record.disposition.key)
        put("disposedAt", record.disposedAt?.toEpochMilli())
        put("disposalAmount", record.disposalAmount)
        put("purchaseID", record.purchaseId?.toString())
        put("purity", record.input.purity)
        put("laborFee", record.input.laborFee)
        put("extraFee", record.input.otherCost)
        put("purchaseTotalOverride", record.input.totalCostOverride)
        put("recoveryDeduction", record.input.rule.perGramDeduction)
        put("recoveryDiscount", record.input.rule.discountRate)
        put("recoveryFixedFee", record.input.rule.fixedFee)
        put("alerts", JSONArray(record.alerts.map(HoldingAlertJson::encode)))
    }

    fun decode(value: JSONObject): HoldingRecord = HoldingRecord(
        id = UUID.fromString(value.getString("id")),
        input = GoldReturnInput(
            grams = value.getDouble("grams"),
            purity = value.optDouble("purity", 1.0),
            unitPrice = value.getDouble("unitPriceCNY"),
            laborFee = value.optDouble("laborFee", 0.0),
            otherCost = value.optDouble("extraFee", 0.0),
            totalCostOverride = value.optional("purchaseTotalOverride", value::getDouble),
            rule = GoldRecoveryRule(
                value.optDouble("recoveryDeduction", 0.0),
                value.optDouble("recoveryDiscount", 0.0),
                value.optDouble("recoveryFixedFee", 0.0),
            ),
        ),
        timestamp = Instant.ofEpochMilli(value.getLong("timestamp")),
        createdAt = Instant.ofEpochMilli(value.getLong("createdAt")),
        bookName = value.optString("bookName", DEFAULT_HOLDING_BOOK),
        assetType = HoldingAssetType.entries.find { it.title == value.optString("assetType") }
            ?: HoldingAssetType.Other,
        brand = value.optString("brand"),
        note = value.optString("note"),
        purchaseChannel = value.optString("purchaseChannel"),
        counterparty = value.optString("counterparty"),
        disposition = HoldingDisposition.entries.find { it.key == value.optString("disposition") }
            ?: HoldingDisposition.Holding,
        disposedAt = value.optional("disposedAt", value::getLong)?.let(Instant::ofEpochMilli),
        disposalAmount = value.optDouble("disposalAmount", 0.0),
        purchaseId = value.optional("purchaseID", value::getString)?.let(UUID::fromString),
        alerts = value.optJSONArray("alerts")?.let { array ->
            List(array.length()) { HoldingAlertJson.decode(array.getJSONObject(it)) }
        }.orEmpty(),
    )

    private fun <T> JSONObject.optional(key: String, getter: (String) -> T): T? =
        if (isNull(key)) null else getter(key)
}
