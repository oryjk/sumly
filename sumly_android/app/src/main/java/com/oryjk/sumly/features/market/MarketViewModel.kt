package com.oryjk.sumly.features.market

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

data class MarketUiState(
    val basis: MarketBasis = MarketBasis.Domestic,
    val range: MarketRange = MarketRange.Quarter,
    val scale: ChartScale = ChartScale.Linear,
    val quote: MarketQuote? = null,
    val quoteLoading: Boolean = true,
    val quoteFailed: Boolean = false,
    val chartLoading: Boolean = true,
    val chartFailed: Boolean = false,
    val pendingBasis: MarketBasis? = null,
    val switchFailed: Boolean = false,
    val observedAt: Instant = Instant.now(),
    internal val observations: List<MarketObservation> = emptyList(),
    internal val realtime: RealtimeWindow? = null,
) {
    internal fun observedDate(zone: ZoneId): LocalDate = observedAt.atZone(zone).toLocalDate()

    internal fun isRealtimePaused(): Boolean =
        range == MarketRange.Realtime && isRealtimeWindowPaused(realtime, quote, observedAt)

    internal fun visiblePoints(zone: ZoneId): List<MarketChartPoint> = if (range == MarketRange.Realtime) {
        realtime?.points.orEmpty()
    } else {
        MarketChartLogic.historicalPoints(observations, basis, range, quote?.usdCny, observedDate(zone), zone)
    }
}

class MarketViewModel(
    private val service: GoldMarketService,
    private val clock: Clock = Clock.systemDefaultZone(),
    initialBasis: MarketBasis = MarketBasis.Domestic,
    private val onBasisSelected: (MarketBasis) -> Unit = {},
    private val computeDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {
    private val mutableState = MutableStateFlow(MarketUiState(basis = initialBasis, observedAt = clock.instant()))
    val uiState: StateFlow<MarketUiState> = mutableState.asStateFlow()
    internal val chartZone: ZoneId get() = clock.zone

    private val quoteRequests = MarketBasis.entries.associateWith { Mutex() }
    private val realtimeRequests = MarketBasis.entries.associateWith { Mutex() }
    private val historyRequests = MarketBasis.entries.associateWith { Mutex() }

    /** One foreground quote stream serves the market, holdings and calendar screens. */
    suspend fun pollQuotes() {
        uiState.map { it.basis }.distinctUntilChanged().collectLatest { basis ->
            val cached = marketAttempt { service.cachedQuote(basis) }
            if (cached != null) updateBasis(basis) { it.copy(quote = it.quote ?: cached) }
            poll({ 5_000L }) { loadQuote(basis) }
        }
    }

    /** History and live chart requests are scoped to the visible chart. */
    internal suspend fun pollCharts() {
        uiState.map { it.basis to (it.range == MarketRange.Realtime) }
            .distinctUntilChanged()
            .collectLatest { (basis, live) ->
                if (!live) {
                    val cached = marketAttempt { service.cachedHistory(basis) }.orEmpty()
                    if (cached.isNotEmpty()) updateBasis(basis) {
                        if (it.observations.isEmpty()) it.copy(observations = cached) else it
                    }
                }
                poll({ if (live) realtimePollInterval() else 60_000L }) { loadChart(basis, live, force = false) }
            }
    }

    fun selectBasis(basis: MarketBasis) {
        val current = uiState.value
        if (current.basis == basis || current.pendingBasis != null) return
        mutableState.update { it.copy(pendingBasis = basis, switchFailed = false) }
        viewModelScope.launch {
            val live = current.range == MarketRange.Realtime
            val next = marketAttempt {
                coroutineScope {
                    val quoteRequest = async { service.fetchQuote(basis) }
                    val chartRequest = async {
                        if (live) {
                            val window = service.fetchRealtime(basis)
                            val usable = withContext(computeDispatcher) {
                                MarketChartLogic.mergeRealtime(null, window, clock.instant())
                            }
                            MarketUiState(realtime = usable)
                        } else {
                            MarketUiState(observations = service.fetchHistory(basis))
                        }
                    }
                    chartRequest.await().copy(
                        basis = basis,
                        range = current.range,
                        scale = current.scale,
                        quote = quoteRequest.await(),
                        quoteLoading = false,
                        chartLoading = false,
                        observedAt = clock.instant(),
                    ).takeIf {
                        it.quote?.cnyPerGram != null && if (live) {
                            it.visiblePoints(chartZone).isNotEmpty()
                        } else {
                            it.observations.isNotEmpty() &&
                                (basis == MarketBasis.Domestic || it.quote.usdCny != null)
                        }
                    }
                }
            }
            mutableState.update { next ?: it.copy(pendingBasis = null, switchFailed = true) }
            if (next != null) onBasisSelected(next.basis)
        }
    }

    fun selectRange(range: MarketRange) = mutableState.update {
        if (it.pendingBasis != null || it.range == range) it else it.copy(
            range = range,
            chartLoading = if (range == MarketRange.Realtime) it.realtime == null else it.observations.isEmpty(),
            chartFailed = false,
            observedAt = clock.instant(),
        )
    }

    fun selectScale(scale: ChartScale) = mutableState.update {
        if (it.pendingBasis != null) it else it.copy(scale = scale)
    }

    fun refresh() {
        val current = uiState.value
        if (current.pendingBasis != null) return
        viewModelScope.launch {
            launch { loadQuote(current.basis) }
            launch { loadChart(current.basis, current.range == MarketRange.Realtime, force = true) }
        }
    }

    internal suspend fun clearCache() {
        service.clearCache()
        mutableState.update { it.copy(observations = emptyList(), realtime = null, chartLoading = true) }
    }

    internal suspend fun quoteForAlerts(basis: MarketBasis): MarketQuote? {
        val state = uiState.value
        return if (state.basis == basis) state.quote else marketAttempt { service.fetchQuote(basis) }
    }

    internal suspend fun historicalPurchasePrice(basis: MarketBasis, day: LocalDate): Double? {
        if (day >= LocalDate.now(clock)) return null
        fun List<MarketObservation>.closingPrice() = firstOrNull {
            it.date == day && it.granularity == MarketGranularity.Daily && !it.deleted
        }?.close?.takeIf { it.isFinite() && it > 0 }
        val close = marketAttempt { service.cachedHistory(basis) }?.closingPrice()
            ?: marketAttempt { service.fetchHistory(basis) }?.closingPrice()
            ?: return null
        val price = when (basis) {
            MarketBasis.Domestic -> close
            MarketBasis.International -> {
                val quote = marketAttempt { service.fetchQuote(basis) }
                    ?: marketAttempt { service.cachedQuote(basis) }
                val rate = quote?.usdCny?.takeIf { it.isFinite() && it > 0 } ?: return null
                close * rate / GRAMS_PER_TROY_OUNCE
            }
        }
        return price.takeIf { it.isFinite() && it > 0 && it <= 1_000_000.0 }
    }

    private suspend fun loadQuote(basis: MarketBasis) {
        val request = quoteRequests.getValue(basis)
        if (!request.tryLock()) return
        try {
            val quote = marketAttempt { service.fetchQuote(basis) }
            val now = clock.instant()
            updateBasis(basis) { state ->
                val existing = state.quote
                val usable = quote?.takeIf { it.cnyPerGram != null && (existing == null || it.asOf >= existing.asOf) }
                val nextQuote = when {
                    usable != null -> if (usable == existing) existing else usable
                    existing != null -> existing
                    else -> quote
                }
                state.copy(
                    quote = nextQuote,
                    quoteLoading = false,
                    quoteFailed = quote == null || usable == null && existing != null,
                    observedAt = nextObservedAt(state, now, nextQuote, state.realtime),
                )
            }
        } finally {
            request.unlock()
        }
    }

    private suspend fun loadChart(basis: MarketBasis, live: Boolean, force: Boolean) {
        val request = (if (live) realtimeRequests else historyRequests).getValue(basis)
        if (!request.tryLock()) return
        try {
            val realtime = if (live) marketAttempt { service.fetchRealtime(basis) } else null
            val history = if (live) null else marketAttempt { service.fetchHistory(basis, force) }
            val now = clock.instant()
            val previous = uiState.value.takeIf { it.basis == basis }?.realtime
            val usableRealtime = realtime?.let { window ->
                withContext(computeDispatcher) { MarketChartLogic.mergeRealtime(previous, window, now) }
            }
            updateBasis(basis) { state ->
                if (live != (state.range == MarketRange.Realtime)) state else {
                    val nextRealtime = when {
                        usableRealtime == null -> state.realtime
                        usableRealtime == state.realtime -> state.realtime
                        else -> usableRealtime
                    }
                    val nextObservations = when {
                        history == null -> state.observations
                        history == state.observations -> state.observations
                        else -> history
                    }
                    state.copy(
                        realtime = nextRealtime,
                        observations = nextObservations,
                        chartLoading = false,
                        chartFailed = if (live) usableRealtime == null else history == null,
                        observedAt = nextObservedAt(state, now, state.quote, nextRealtime),
                    )
                }
            }
        } finally {
            request.unlock()
        }
    }

    private fun nextObservedAt(
        state: MarketUiState,
        now: Instant,
        nextQuote: MarketQuote?,
        nextRealtime: RealtimeWindow?,
    ): Instant {
        if (now.atZone(chartZone).toLocalDate() != state.observedDate(chartZone)) return now
        if (state.range != MarketRange.Realtime) return state.observedAt
        if (nextRealtime != state.realtime) return now
        val pausedAtPrevious = isRealtimeWindowPaused(nextRealtime, nextQuote, state.observedAt)
        val pausedNow = isRealtimeWindowPaused(nextRealtime, nextQuote, now)
        return if (pausedAtPrevious != pausedNow) now else state.observedAt
    }

    private inline fun updateBasis(basis: MarketBasis, transform: (MarketUiState) -> MarketUiState) {
        mutableState.update { if (it.basis == basis) transform(it) else it }
    }

    private fun realtimePollInterval(): Long {
        val state = uiState.value
        val window = state.realtime ?: return 5_000L
        val latest = window.points.lastOrNull() ?: return 5_000L
        val paused = MarketChartLogic.isPaused(latest.time, state.quote?.asOf, window.intervalSeconds, clock.instant())
        return if (paused) 30_000L else 5_000L
    }

    private suspend fun poll(intervalMillis: () -> Long, operation: suspend () -> Unit) {
        while (true) {
            operation()
            delay(intervalMillis())
        }
    }
}

private fun isRealtimeWindowPaused(realtime: RealtimeWindow?, quote: MarketQuote?, at: Instant): Boolean {
    val window = realtime ?: return false
    val latest = window.points.lastOrNull()?.time ?: return false
    return MarketChartLogic.isPaused(latest, quote?.asOf, window.intervalSeconds, at)
}

private suspend fun <T> marketAttempt(operation: suspend () -> T): T? = try {
    operation()
} catch (cancelled: CancellationException) {
    throw cancelled
} catch (_: Exception) {
    null
}
