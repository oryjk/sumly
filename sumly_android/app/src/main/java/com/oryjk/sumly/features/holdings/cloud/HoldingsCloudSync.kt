package com.oryjk.sumly.features.holdings.cloud

import com.oryjk.sumly.features.holdings.HoldingsStore
import java.io.IOException
import java.time.Clock
import java.time.Instant
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

internal interface HoldingsCloudRemote {
    suspend fun fetch(): HoldingsCloudSnapshot
    suspend fun put(expectedRevision: Long, document: HoldingsCloudDocument): HoldingsCloudSnapshot
}

internal class HoldingsRevisionConflict : IOException()

data class HoldingsSyncState(
    val isSyncing: Boolean = false,
    val conflictCount: Int = 0,
    val conflictToken: Long? = null,
    val notice: String? = null,
    val lastSyncedAt: Instant? = null,
    val hasLocalChanges: Boolean = false,
)

/** Each worker owns one authenticated workspace and serializes its synchronization attempts. */
internal class HoldingsCloudSync(
    private val store: AccountHoldingsStore,
    private val remote: HoldingsCloudRemote,
    private val isCurrent: () -> Boolean,
    private val clock: Clock = Clock.systemUTC(),
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private data class Conflict(
        val local: HoldingsCloudDocument,
        val base: HoldingsCloudSnapshot,
        val remote: HoldingsCloudSnapshot,
    )

    private data class Decision(val conflict: Conflict, val choice: HoldingsConflictChoice)

    private data class PendingConflict(val token: Long, val conflict: Conflict)

    private data class Accepted(
        val document: HoldingsCloudDocument,
        val conflict: Conflict? = null,
        val conflictCount: Int = 0,
    )

    private val stateModel = MutableStateFlow(HoldingsSyncState())
    val state = stateModel.asStateFlow()
    private val syncLock = Mutex()
    @Volatile private var pendingConflict: PendingConflict? = null
    @Volatile private var nextAttempt = Instant.MIN
    @Volatile private var lastChecked = Instant.MIN

    suspend fun run() {
        sync()
        while (isCurrent()) {
            delay(3_000)
            val dirty = store.hasLocalChanges.value
            stateModel.update { it.copy(hasLocalChanges = dirty) }
            val now = clock.instant()
            if (isCurrent() && pendingConflict == null && now >= nextAttempt && (dirty || now >= lastChecked.plusSeconds(60))) {
                sync()
            }
        }
    }

    suspend fun sync() = synchronize(null)

    suspend fun resolveConflict(token: Long, choice: HoldingsConflictChoice) {
        val displayed = pendingConflict?.takeIf { it.token == token } ?: return
        // The latest GET and the current stored draft must also match this dialog.
        synchronize(Decision(displayed.conflict, choice))
    }

    private suspend fun synchronize(requestedDecision: Decision?) {
        if (!isCurrent()) return
        if (!syncLock.tryLock()) return
        var decision = requestedDecision
        stateModel.update { it.copy(isSyncing = true, notice = null, hasLocalChanges = store.hasLocalChanges.value) }
        try {
            repeat(3) {
                ensureCurrent()
                val cloud = remote.fetch().validated()
                ensureCurrent()
                lastChecked = clock.instant()
                val accepted = cacheTransaction { data ->
                    require(cloud.revision > data.base.revision || cloud == data.base) { "Remote revision regressed" }
                    val candidate = Conflict(data.local, data.base, cloud)
                    val recordedChoice = decision?.takeIf { it.conflict == candidate }?.choice
                    val merged = HoldingsCloudMerge.merge(data.base.document, data.local, cloud.document, recordedChoice)
                    if (merged.conflicts.isNotEmpty() && recordedChoice == null) {
                        data to Accepted(data.local, candidate, merged.conflicts.size)
                    } else {
                        val local = merged.document.validate()
                        data.copy(base = cloud, local = local) to Accepted(local)
                    }
                }
                ensureCurrent()
                val pending = accepted.conflict?.let { conflict ->
                    pendingConflict?.takeIf { it.conflict == conflict }
                        ?: PendingConflict(conflictTokens.incrementAndGet(), conflict)
                }
                pendingConflict = pending
                stateModel.update { it.copy(conflictCount = accepted.conflictCount, conflictToken = pending?.token) }
                if (accepted.conflict != null) return

                decision = null
                if (accepted.document != cloud.document) {
                    val saved = try {
                        remote.put(cloud.revision, accepted.document).validated()
                    } catch (_: HoldingsRevisionConflict) {
                        return@repeat
                    }
                    require(saved.revision == cloud.revision + 1 && saved.document == accepted.document)
                    cacheTransaction { data ->
                        require(data.base == cloud)
                        // The cloud acknowledged exactly what was sent. Any local
                        // editing after submission is still pending against that base.
                        data.copy(base = saved) to Unit
                    }
                }
                ensureCurrent()
                nextAttempt = Instant.MIN
                stateModel.update { it.copy(lastSyncedAt = clock.instant()) }
                return
            }
            throw HoldingsRevisionConflict()
        } catch (_: HoldingsWorkspaceRetired) {
            // A retired account cannot write after its session changed or its cache was erased.
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (isCurrent()) {
                nextAttempt = clock.instant().plusSeconds(60)
                stateModel.update {
                    val reason = if (error is HoldingsRevisionConflict) "云端账本刚刚更新。" else "暂时无法同步云端。"
                    it.copy(notice = "${reason}本机记录已保留，稍后重试。")
                }
            }
        } finally {
            stateModel.update { it.copy(isSyncing = false, hasLocalChanges = store.hasLocalChanges.value) }
            syncLock.unlock()
        }
    }

    suspend fun importGuestRecords(guestStore: HoldingsStore) {
        try {
            withContext(ioDispatcher) {
                ensureCurrent()
                val guest = guestStore.load()
                ensureCurrent()
                store.importGuestRecords(guest)
            }
        } catch (_: HoldingsWorkspaceRetired) {
            return
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            if (isCurrent()) stateModel.update { it.copy(notice = "游客记录导入失败，请重试。") }
            return
        }
        sync()
    }

    private suspend fun <T> cacheTransaction(change: (AccountHoldingsData) -> Pair<AccountHoldingsData, T>): T =
        withContext(ioDispatcher) {
            val job = currentCoroutineContext()[Job]
            store.accountTransaction(stillCurrent = { job?.isActive != false && isCurrent() }, change = change)
        }

    private suspend fun ensureCurrent() {
        currentCoroutineContext().ensureActive()
        if (!isCurrent()) throw HoldingsWorkspaceRetired()
    }

    private fun HoldingsCloudSnapshot.validated() = validate().copy(document = document.normalized().validate())

    private companion object {
        val conflictTokens = AtomicLong()
    }
}
