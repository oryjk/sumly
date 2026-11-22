package com.oryjk.sumly.features.holdings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.oryjk.sumly.features.holdings.alerts.HoldingAlert
import com.oryjk.sumly.features.holdings.cloud.HoldingsLocalConflict
import com.oryjk.sumly.features.market.MarketBasis
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class HoldingsState(
    val snapshot: HoldingsSnapshot = HoldingsSnapshot(),
    val referencePrice: Double? = null,
    val previousPrice: Double? = null,
    val marketBasis: MarketBasis = MarketBasis.Domestic,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val loadFailed: Boolean = false,
    val error: String? = null,
) {
    val currentBook: String get() = snapshot.currentBook
    val referenceBasis: String get() = "${marketBasis.label}金价"
}

class HoldingsViewModel(
    private val store: HoldingsStore,
    private val clock: Clock = Clock.systemDefaultZone(),
    private val snapshots: StateFlow<HoldingsSnapshot?>? = null,
    private val historicalPrice: suspend (MarketBasis, LocalDate) -> Double? = { _, _ -> null },
) : ViewModel() {
    private val mutableState = MutableStateFlow(HoldingsState())
    val state: StateFlow<HoldingsState> = mutableState.asStateFlow()

    init {
        if (snapshots != null) {
            viewModelScope.launch {
                snapshots.filterNotNull().collect { snapshot ->
                    mutableState.update { it.copy(snapshot = snapshot, isLoading = false, loadFailed = false) }
                }
            }
        }
        reload()
    }

    fun setReferencePrice(price: Double?, basis: MarketBasis, previousPrice: Double?) {
        mutableState.update {
            it.copy(
                referencePrice = GoldReturnCalculator.validPrice(price),
                previousPrice = GoldReturnCalculator.validPrice(previousPrice),
                marketBasis = basis,
            )
        }
    }

    internal suspend fun historicalPurchasePrice(basis: MarketBasis, date: LocalDate): Double? =
        historicalPrice(basis, date)

    fun reload() {
        if (state.value.isSaving) return
        mutableState.update { it.copy(isLoading = true, error = null) }
        viewModelScope.launch {
            try {
                val snapshot = withContext(Dispatchers.IO) { store.load() }
                mutableState.update { it.copy(snapshot = snapshots?.value ?: snapshot, isLoading = false, loadFailed = false) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                mutableState.update {
                    it.copy(isLoading = false, loadFailed = true, error = "无法读取本机持仓")
                }
            }
        }
    }

    fun selectBook(book: String) {
        val current = state.value
        if (book in current.snapshot.books && book != current.currentBook) {
            performWrite({ setCurrentBook(book) })
        }
    }

    fun createBook(name: String, onComplete: () -> Unit) {
        val normalized = name.trim()
        if (normalized.isEmpty()) return
        performWrite({ createBook(normalized) }) { onComplete() }
    }

    fun togglePrivacy() {
        val hidden = state.value.snapshot.amountsHidden
        performWrite({ setAmountsHidden(!hidden) })
    }

    internal fun save(draft: HoldingDraft, existing: HoldingRecord?, onComplete: (HoldingReceiptSnapshot?) -> Unit) {
        val now = clock.instant()
        val input = draft.input() ?: return
        val current = state.value.snapshot
        if (draft.bookName !in current.books || draft.timestamp > now ||
            (existing?.disposedAt?.let { draft.timestamp > it } == true)
        ) {
            mutableState.update { it.copy(error = "请检查账本及记录日期") }
            return
        }

        val record = (existing ?: HoldingRecord(input = input, timestamp = draft.timestamp, createdAt = now))
            .copy(
                input = input,
                timestamp = draft.timestamp,
                bookName = draft.bookName,
                assetType = draft.assetType,
                brand = draft.brand.trim(),
                note = draft.note.trim(),
                purchaseChannel = draft.channel.trim(),
            )
        performWrite({ saveRecordsIfUnchanged(existing, listOf(record)) }) { written ->
            onComplete(if (existing == null) HoldingReceiptSnapshot.from(record, written) else null)
        }
    }

    fun dispose(
        existing: HoldingRecord,
        grams: Double,
        kind: HoldingDisposition,
        proceeds: Double,
        date: Instant,
        counterparty: String,
        onComplete: () -> Unit,
    ) {
        val items = HoldingDisposal.apply(
            record = existing, grams = grams, kind = kind, proceeds = proceeds,
            date = date, now = clock.instant(), counterparty = counterparty.trim(),
        )
        if (items == null) {
            mutableState.update { it.copy(error = "请检查克重、实收金额及处置日期") }
            return
        }
        performWrite({ saveRecordsIfUnchanged(existing, items) }) { onComplete() }
    }

    fun delete(existing: HoldingRecord, onComplete: () -> Unit) {
        performWrite({ deleteRecordIfUnchanged(existing) }) { onComplete() }
    }

    internal fun saveAlerts(expected: HoldingRecord, alerts: List<HoldingAlert>, onComplete: () -> Unit) {
        performWrite({ saveRecordsIfUnchanged(expected, listOf(expected.copy(alerts = alerts))) }) { onComplete() }
    }

    fun dismissError() {
        mutableState.update { it.copy(error = null) }
    }

    private fun performWrite(
        operation: HoldingsStore.() -> HoldingsSnapshot,
        onComplete: (HoldingsSnapshot) -> Unit = {},
    ) {
        val current = state.value
        if (current.isSaving || current.isLoading || current.loadFailed) return
        mutableState.update { it.copy(isSaving = true, error = null) }
        viewModelScope.launch {
            val snapshot = try {
                withContext(Dispatchers.IO) { store.operation() }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: HoldingsLocalConflict) {
                mutableState.update { it.copy(isSaving = false, error = "该记录已同步更新，请重新打开后再操作。") }
                return@launch
            } catch (_: Exception) {
                mutableState.update { it.copy(isSaving = false, error = "本机记录保存失败，请重试") }
                return@launch
            }
            mutableState.update { it.copy(snapshot = snapshots?.value ?: snapshot, isSaving = false) }
            onComplete(snapshot)
        }
    }

}
