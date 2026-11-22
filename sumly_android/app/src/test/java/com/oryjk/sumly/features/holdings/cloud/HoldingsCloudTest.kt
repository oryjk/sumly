package com.oryjk.sumly.features.holdings.cloud

import com.oryjk.sumly.features.holdings.DEFAULT_HOLDING_BOOK
import com.oryjk.sumly.features.holdings.GoldReturnInput
import com.oryjk.sumly.features.holdings.HoldingAssetType
import com.oryjk.sumly.features.holdings.HoldingDisposition
import com.oryjk.sumly.features.holdings.HoldingDisposal
import com.oryjk.sumly.features.holdings.HoldingRecord
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class HoldingsCloudTest {
    @get:Rule val files = TemporaryFolder()

    @Test
    fun persistencePreservesIosOnlyFieldsFractionalTimestampsAndRevisionAcrossUnrelatedEdit() = runTest {
        val path = files.root.resolve("owner-32.json")
        val store = AccountHoldingsStore(path)
        val remote = FakeRemote(HoldingCloudWire.decodeSnapshot(wireFixture()))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))

        sync.sync()
        val recreated = AccountHoldingsStore(path)
        val original = recreated.load().records.single { it.disposition == HoldingDisposition.Holding }
        assertEquals(HoldingAssetType.Other, original.assetType)
        recreated.saveRecords(listOf(original.copy(note = "Android 编辑备注")))
        HoldingsCloudSync(recreated, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler)).sync()

        val saved = HoldingCloudWire.encodeSnapshot(remote.snapshot)
        val records = saved.getJSONObject("document").getJSONArray("records")
        val wire = records.getJSONObject(0)
        assertEquals(9_007_199_254_740_996L, saved.getLong("revision"))
        assertEquals("历史类型", wire.getString("assetType"))
        assertEquals(1_790_500_000_000.125, wire.getDouble("timestamp"), 0.0)
        assertEquals(-125.0, wire.getDouble("createdAt"), 0.0)
        assertEquals("international", wire.getJSONArray("alerts").getJSONObject(0).getString("basis"))
        assertEquals("Android 编辑备注", wire.getString("note"))
        val sold = records.getJSONObject(1)
        assertEquals(wire.getString("id"), sold.getString("purchaseID"))
        assertEquals(1_790_500_010_000.875, sold.getDouble("disposedAt"), 0.0)
        assertEquals("门店", sold.getString("counterparty"))
        assertEquals("iOS sale", sold.getString("note"))
        assertEquals(1, remote.puts)
    }

    @Test
    fun conflictingPartialDisposalsAreOneFamilyAndRequireResolution() = runTest {
        val store = AccountHoldingsStore(files.root.resolve("owner-3.json"))
        val base = holding("base", 10.0)
        val remote = FakeRemote(snapshot(1, base))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        val splitDate = base.timestamp.plusSeconds(5)
        sync.sync()
        val android = HoldingDisposal.apply(base, 3.0, HoldingDisposition.Sold, 30.0, splitDate, splitDate)!!
        val ios = HoldingDisposal.apply(base, 4.0, HoldingDisposition.Gift, 0.0, splitDate, splitDate)!!
        store.saveRecords(android)
        remote.snapshot = snapshot(2, *ios.toTypedArray())

        sync.sync()

        assertEquals(3, sync.state.value.conflictCount)
        assertEquals(0, remote.puts)
        assertEquals(android.map { it.id }.toSet(), store.load().records.map { it.id }.toSet())

        sync.resolveConflict(requireNotNull(sync.state.value.conflictToken), HoldingsConflictChoice.Cloud)

        assertEquals(ios.map { it.id }.toSet(), store.load().records.map { it.id }.toSet())
        assertEquals(10.0, store.load().records.sumOf { it.input.grams }, 0.0)
        assertEquals(0, sync.state.value.conflictCount)
    }

    @Test
    fun staleResolutionDoesNotOverwriteCloudAfterAnotherDeviceEditsAgain() = runTest {
        val base = holding("base")
        val remote = FakeRemote(snapshot(1, base))
        val store = AccountHoldingsStore(files.root.resolve("owner-4.json"))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        sync.sync()
        store.saveRecords(listOf(base.copy(note = "local")))
        remote.snapshot = snapshot(2, base.copy(note = "first remote"))
        sync.sync()
        assertEquals(1, sync.state.value.conflictCount)
        val token = requireNotNull(sync.state.value.conflictToken)
        remote.snapshot = snapshot(3, base.copy(note = "new remote"))

        sync.resolveConflict(token, HoldingsConflictChoice.Local)

        assertEquals(0, remote.puts)
        assertEquals("new remote", remote.snapshot.document.records.single().holding.note)
        assertEquals(1, sync.state.value.conflictCount)
        assertTrue(token != sync.state.value.conflictToken)

        // A still-open confirmation must also be rejected after a different
        // conflict has already been discovered, even when the count is unchanged.
        sync.resolveConflict(token, HoldingsConflictChoice.Local)

        assertEquals(0, remote.puts)
        assertEquals("new remote", remote.snapshot.document.records.single().holding.note)
    }

    @Test
    fun casRetryMergesNewRemoteRecordAndKeepsLocalEditMadeDuringUpload() = runTest {
        val path = files.root.resolve("owner-5.json")
        val store = AccountHoldingsStore(path)
        val local = holding("from Android")
        val fromIos = holding("from iOS")
        val remote = FakeRemote(snapshot(0))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        store.saveRecords(listOf(local))
        remote.beforePut = { count ->
            if (count == 1) {
                remote.snapshot = snapshot(1, fromIos)
            } else {
                store.saveRecords(listOf(local.copy(note = "edited while PUT was in flight")))
            }
        }

        sync.sync()

        assertEquals(2, remote.puts)
        assertEquals(setOf(local.id, fromIos.id), remote.snapshot.document.records.map { it.id }.toSet())
        assertEquals("from Android", remote.snapshot.document.records.first { it.id == local.id }.holding.note)
        val reopened = AccountHoldingsStore(path)
        assertEquals("edited while PUT was in flight", reopened.load().records.first { it.id == local.id }.note)
        assertTrue(reopened.hasLocalChanges.value)
    }

    @Test
    fun committedPutWithLostResponseRecognizesNewRemoteEditAfterAppRestart() = runTest {
        val path = files.root.resolve("owner-8.json")
        val store = AccountHoldingsStore(path)
        val local = holding("from Android")
        val remote = FakeRemote(snapshot(0))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        store.saveRecords(listOf(local))
        remote.afterPut = { throw java.io.IOException("network response lost") }
        sync.sync()
        assertEquals(1L, remote.snapshot.revision)

        remote.afterPut = null
        remote.snapshot = snapshot(2, local.copy(note = "iOS edited synchronized record"))
        val reopened = AccountHoldingsStore(path)
        val restarted = HoldingsCloudSync(reopened, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        restarted.sync()

        // The app cannot prove this revision descends from its attempted PUT. Preserve both versions.
        assertEquals(1, restarted.state.value.conflictCount)
        assertEquals("from Android", reopened.load().records.single().note)
        assertEquals(1, remote.puts)
    }

    @Test
    fun oldNetworkResponseDoesNotWriteAndErasedWorkspaceCannotRecreateItsCache() = runTest {
        val path = files.root.resolve("owner-6.json")
        var current = true
        val store = AccountHoldingsStore(path) { current }
        val retained = holding("before account switch")
        store.saveRecords(listOf(retained))
        val remote = FakeRemote(snapshot(5, holding("late remote response")))
        remote.beforeGet = { current = false }
        val sync = HoldingsCloudSync(store, remote, { current }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        sync.sync()

        assertEquals(listOf(retained.id), AccountHoldingsStore(path).load().records.map { it.id })
        AccountHoldingsStore.erase(path)
        current = true
        assertThrows(IllegalStateException::class.java) { store.saveRecords(listOf(retained)) }
        assertFalse(path.exists())
        assertThrows(IllegalStateException::class.java) { AccountHoldingsStore(path).load() }
    }

    @Test
    fun guestImportIsIdempotentAndDoesNotModifyVisitorStore() {
        val account = AccountHoldingsStore(files.root.resolve("owner-7.json"))
        val guest = AccountHoldingsStore(files.root.resolve("guest-test.json"))
        val item = holding("guest")
        guest.saveRecords(listOf(item))
        account.importGuestRecords(guest.load())
        account.saveRecords(listOf(item.copy(note = "edited on account")))
        account.importGuestRecords(guest.load())

        assertEquals("edited on account", account.load().records.single().note)
        assertEquals("guest", guest.load().records.single().note)
    }

    @Test
    fun localCompareAndSwapRejectsADraftBasedOnARecordAlreadyUpdatedBySync() = runTest {
        val store = AccountHoldingsStore(files.root.resolve("owner-9.json"))
        val base = holding("original")
        val remote = FakeRemote(snapshot(1, base))
        val sync = HoldingsCloudSync(store, remote, { true }, ioDispatcher = UnconfinedTestDispatcher(testScheduler))
        sync.sync()
        val stale = store.load().records.single()
        remote.snapshot = snapshot(2, base.copy(brand = "iOS updated brand"))
        sync.sync()

        assertThrows(HoldingsLocalConflict::class.java) {
            store.saveRecordsIfUnchanged(stale, listOf(stale.copy(note = "local edit started before sync")))
        }
        assertThrows(HoldingsLocalConflict::class.java) { store.deleteRecordIfUnchanged(stale) }
        assertEquals("iOS updated brand", store.load().records.single().brand)
        assertEquals("original", store.load().records.single().note)
        assertFalse(store.hasLocalChanges.value)
    }

    @Test
    fun unrecognizedCloudRecordFieldsAreRejectedBeforeAnyWriteBack() {
        val snapshot = wireFixture()
        val record = snapshot.getJSONObject("document").getJSONArray("records").getJSONObject(0)
        record.put("futureField", "preserve on the server")

        assertThrows(IllegalArgumentException::class.java) { HoldingCloudWire.decodeSnapshot(snapshot) }
    }

    private class FakeRemote(var snapshot: HoldingsCloudSnapshot) : HoldingsCloudRemote {
        var puts = 0
        var beforeGet: (() -> Unit)? = null
        var beforePut: ((Int) -> Unit)? = null
        var afterPut: (() -> Unit)? = null
        override suspend fun fetch(): HoldingsCloudSnapshot {
            beforeGet?.invoke()
            return snapshot
        }

        override suspend fun put(expectedRevision: Long, document: HoldingsCloudDocument): HoldingsCloudSnapshot {
            puts += 1
            beforePut?.invoke(puts)
            if (expectedRevision != snapshot.revision) throw HoldingsRevisionConflict()
            val result = HoldingsCloudSnapshot(expectedRevision + 1, document)
            snapshot = result
            afterPut?.invoke()
            return result
        }
    }

    private fun snapshot(revision: Long, vararg records: HoldingRecord) = HoldingsCloudSnapshot(
        revision, HoldingsCloudDocument(listOf(DEFAULT_HOLDING_BOOK), records.map { HoldingCloudRecord.fromHolding(it) }).normalized(),
    )

    private fun holding(note: String, grams: Double = 1.0) = HoldingRecord(
        id = UUID.randomUUID(), input = GoldReturnInput(grams = grams, unitPrice = 10.0),
        timestamp = Instant.parse("2026-09-21T09:00:00Z"), note = note,
    )

    // Generated by the iOS HoldingCloudCoding encoder using a purchase and its partial disposal.
    private fun wireFixture() = JSONObject(
        """{"document":{"books":["默认账本"],"records":[
        {"alerts":[{"basis":"international","enabled":true,"id":"0A55850D-3922-4DC5-A9E3-688A4E272C8E","kind":"price","threshold":523.4}],
        "assetType":"历史类型","bookName":"默认账本","brand":"品牌","counterparty":"","createdAt":-125,
        "disposalAmount":0,"disposition":"holding","extraFee":9.25,"grams":5.125,"id":"FC9A5D38-AC13-4D0C-92C7-26F2DA78EF08",
        "laborFee":60.7,"note":"iOS note","purchaseChannel":"线上","purchaseTotalOverride":2300.12,"purity":0.9999,
        "recoveryDeduction":1.25,"recoveryDiscount":0.03,"recoveryFixedFee":6.6,"timestamp":1790500000000.125,"unitPriceCNY":430.5},
        {"alerts":[],"assetType":"其他","bookName":"默认账本","brand":"","counterparty":"门店","createdAt":1790500010000.625,
        "disposalAmount":510,"disposedAt":1790500010000.875,"disposition":"sold","extraFee":0,"grams":1,
        "id":"FCA8C415-ADB3-4F40-971E-E8F5977816CB","laborFee":0,"note":"iOS sale","purchaseChannel":"",
        "purchaseID":"FC9A5D38-AC13-4D0C-92C7-26F2DA78EF08","purity":1,"recoveryDeduction":0,"recoveryDiscount":0,
        "recoveryFixedFee":0,"timestamp":1790500000000.125,"unitPriceCNY":430.5}],"schemaVersion":1},"revision":9007199254740995}""",
    )
}
