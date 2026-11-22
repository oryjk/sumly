package com.oryjk.sumly.features.holdings.cloud

import android.content.Context
import com.oryjk.sumly.features.holdings.DEFAULT_HOLDING_BOOK
import com.oryjk.sumly.features.holdings.HoldingRecord
import com.oryjk.sumly.features.holdings.HoldingsSnapshot
import com.oryjk.sumly.features.holdings.HoldingsStore
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

internal class HoldingsWorkspaceRetired : IllegalStateException()
class HoldingsLocalConflict : IllegalStateException()

internal data class AccountHoldingsData(
    val base: HoldingsCloudSnapshot = HoldingsCloudSnapshot.Empty,
    val local: HoldingsCloudDocument = HoldingsCloudDocument.Empty,
    val amountsHidden: Boolean = false,
    val currentBook: String = DEFAULT_HOLDING_BOOK,
) {
    fun snapshot() = HoldingsSnapshot(
        books = listOf(DEFAULT_HOLDING_BOOK) + local.books.filterNot { it == DEFAULT_HOLDING_BOOK },
        records = local.records.map { it.holding }.sortedByDescending { it.timestamp },
        amountsHidden = amountsHidden,
        currentBook = currentBook.takeIf { it in local.books } ?: DEFAULT_HOLDING_BOOK,
    )
}

/** One atomic file per user contains the local document, merge ancestor and preferences. */
class AccountHoldingsStore internal constructor(
    private val file: File,
    private val isCurrent: () -> Boolean = { true },
) : HoldingsStore {
    constructor(context: Context, userId: Long, isCurrent: () -> Boolean = { true }) :
        this(accountFile(context, userId), isCurrent)

    private val pathKey = file.absoluteFile.toPath().normalize().toString()
    private val publishedSnapshot = MutableStateFlow<HoldingsSnapshot?>(null)
    private val publishedDirty = MutableStateFlow(false)
    val snapshots = publishedSnapshot.asStateFlow()
    val hasLocalChanges = publishedDirty.asStateFlow()

    override fun load(): HoldingsSnapshot = accountTransaction { it to it.snapshot() }

    override fun saveRecords(records: List<HoldingRecord>): HoldingsSnapshot = saveRecords(records) { }

    override fun saveRecordsIfUnchanged(expected: HoldingRecord?, records: List<HoldingRecord>): HoldingsSnapshot {
        require(expected == null || records.any { it.id == expected.id })
        return saveRecords(records) { originals ->
            if ((expected != null && originals[expected.id]?.holding != expected) ||
                records.any { it.id != expected?.id && it.id in originals }
            ) throw HoldingsLocalConflict()
        }
    }

    private fun saveRecords(
        records: List<HoldingRecord>,
        checkOriginals: (Map<UUID, HoldingCloudRecord>) -> Unit,
    ): HoldingsSnapshot {
        require(records.distinctBy { it.id }.size == records.size)
        return update { data ->
            val originals = data.local.records.associateBy { it.id }
            checkOriginals(originals)
            val changes = records.map { record ->
                val purchase = record.purchaseId?.let { id ->
                    originals[id] ?: originals.values.firstOrNull { it.holding.purchaseId == id }
                }
                HoldingCloudRecord.fromHolding(record, originals[record.id], purchase)
            }.associateBy { it.id }
            data.copy(local = HoldingsCloudDocument(
                books = data.local.books + records.map { it.bookName },
                records = (originals + changes).values.toList(),
            ).normalized())
        }
    }

    override fun deleteRecord(id: UUID): HoldingsSnapshot = deleteRecord(id) { }

    override fun deleteRecordIfUnchanged(expected: HoldingRecord): HoldingsSnapshot = deleteRecord(expected.id) { original ->
        if (original?.holding != expected) throw HoldingsLocalConflict()
    }

    private fun deleteRecord(id: UUID, checkOriginal: (HoldingCloudRecord?) -> Unit): HoldingsSnapshot = update { data ->
        checkOriginal(data.local.records.firstOrNull { it.id == id })
        data.copy(local = data.local.copy(records = data.local.records.filterNot { it.id == id }))
    }

    override fun createBook(name: String): HoldingsSnapshot = update { data ->
        data.copy(local = data.local.copy(books = data.local.books + name).normalized(), currentBook = name)
    }

    override fun setCurrentBook(name: String): HoldingsSnapshot = update { data ->
        require(name in data.local.books)
        data.copy(currentBook = name)
    }

    override fun setAmountsHidden(hidden: Boolean): HoldingsSnapshot = update { data -> data.copy(amountsHidden = hidden) }

    internal fun importGuestRecords(guest: HoldingsSnapshot): HoldingsSnapshot = update { data ->
        val existing = data.local.records.mapTo(mutableSetOf()) { it.id }
        val additions = guest.records.filter { existing.add(it.id) }.map { HoldingCloudRecord.fromHolding(it) }
        val books = data.local.books + guest.books + additions.map { it.holding.bookName }
        data.copy(local = HoldingsCloudDocument(books, data.local.records + additions).normalized())
    }

    private fun update(change: (AccountHoldingsData) -> AccountHoldingsData): HoldingsSnapshot = accountTransaction { before ->
        val after = change(before)
        after to after.snapshot()
    }

    internal fun <T> accountTransaction(
        stillCurrent: () -> Boolean = { true },
        change: (AccountHoldingsData) -> Pair<AccountHoldingsData, T>,
    ): T = synchronized(diskLock) {
        fun guard() {
            if (!isCurrent() || !stillCurrent() || pathKey in erasedFiles) throw HoldingsWorkspaceRetired()
        }

        guard()
        val before = readData()
        val (after, result) = change(before)
        guard()
        if (after != before) saveData(after, ::guard)
        publishedSnapshot.value = after.snapshot()
        publishedDirty.value = after.local != after.base.document
        result
    }

    private fun readData(): AccountHoldingsData {
        if (!file.exists()) return AccountHoldingsData()
        if (file.length() > MaxCacheBytes) throw IOException("本机账户账本大小异常。")
        val json = JSONObject(file.readText(Charsets.UTF_8))
        require(json.getInt("formatVersion") == 1)
        return AccountHoldingsData(
            base = HoldingCloudWire.decodeSnapshot(json.getJSONObject("base")),
            local = HoldingCloudWire.decodeDocument(json.getJSONObject("local")),
            amountsHidden = json.getBoolean("amountsHidden"),
            currentBook = json.getString("currentBook"),
        )
    }

    private fun saveData(data: AccountHoldingsData, guard: () -> Unit) {
        val base = HoldingCloudWire.encodeSnapshot(data.base.validate())
        val local = HoldingCloudWire.encodeDocument(data.local.validate())
        if (local.toString().toByteArray(Charsets.UTF_8).size > HoldingsCloudMaxBytes ||
            base.toString().toByteArray(Charsets.UTF_8).size > HoldingsCloudMaxBytes
        ) throw IOException("账户账本记录过大。")
        val contents = JSONObject()
            .put("formatVersion", 1)
            .put("base", base)
            .put("local", local)
            .put("amountsHidden", data.amountsHidden)
            .put("currentBook", data.currentBook)
            .toString().toByteArray(Charsets.UTF_8)
        if (contents.size > MaxCacheBytes) throw IOException("本机账户账本大小异常。")

        val parent = file.parentFile ?: error("Missing account cache directory")
        if (!parent.isDirectory && !parent.mkdirs()) throw IOException("无法打开本机账户账本。")
        val pending = pendingFile(file)
        try {
            FileOutputStream(pending).use { stream ->
                stream.write(contents)
                stream.fd.sync()
            }
            guard()
            Files.move(pending.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            pending.delete()
        }
    }

    companion object {
        private const val MaxCacheBytes = 2L * HoldingsCloudMaxBytes + 4096
        private val diskLock = Any()
        private val erasedFiles = mutableSetOf<String>()

        /** A confirmed account deletion also retires in-flight access to this user ID. */
        fun erase(context: Context, userId: Long) = erase(accountFile(context, userId))

        internal fun erase(file: File) = synchronized(diskLock) {
            erasedFiles.add(file.absoluteFile.toPath().normalize().toString())
            Files.deleteIfExists(file.toPath())
            Files.deleteIfExists(pendingFile(file).toPath())
            Unit
        }

        private fun accountFile(context: Context, userId: Long): File {
            require(userId > 0)
            return File(context.applicationContext.filesDir, "holding-accounts/user-$userId.json")
        }

        private fun pendingFile(file: File) = File(file.parentFile, file.name + ".pending")
    }
}
