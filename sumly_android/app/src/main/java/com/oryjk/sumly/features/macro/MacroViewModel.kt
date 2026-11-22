package com.oryjk.sumly.features.macro

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal enum class MacroTab(val title: String) {
    Temperature("黄金温度"), Treasury("美国国债"), Panorama("宏观全景"),
}

internal data class MacroPanel<T>(val result: T? = null, val loading: Boolean = false, val failed: Boolean = false)

internal data class MacroQuery(val range: MacroRange, val seriesId: String? = null)

internal data class MacroHistoryPanel<T>(val query: MacroQuery, val panel: MacroPanel<T> = MacroPanel())

internal data class MacroUiState(
    val temperature: MacroPanel<TemperatureSnapshot> = MacroPanel(),
    val panorama: MacroPanel<List<MacroSection>> = MacroPanel(),
    val history: MacroHistoryPanel<TemperatureHistory> = MacroHistoryPanel(MacroQuery(MacroRange.ThreeYears)),
    val treasury: MacroHistoryPanel<TreasuryReport> = MacroHistoryPanel(MacroQuery(MacroRange.FiveYears)),
    val cot: MacroHistoryPanel<MacroCotReport> = MacroHistoryPanel(MacroQuery(MacroRange.ThreeYears)),
    val detail: MacroHistoryPanel<MacroIndicatorDetail> = MacroHistoryPanel(MacroQuery(MacroRange.FiveYears)),
)

internal class MacroViewModel(private val service: MacroService) : ViewModel() {
    private val model = MutableStateFlow(MacroUiState())
    val state = model.asStateFlow()
    private var historyRequest: Job? = null
    private var treasuryRequest: Job? = null
    private var cotRequest: Job? = null
    private var detailRequest: Job? = null

    fun load(tab: MacroTab, force: Boolean = false) {
        when (tab) {
            MacroTab.Temperature -> request(force, MacroUiState::temperature, { state, panel -> state.copy(temperature = panel) }, service::temperature)
            MacroTab.Treasury -> loadTreasury(model.value.treasury.query.range, force)
            MacroTab.Panorama -> {
                request(force, MacroUiState::panorama, { state, panel -> state.copy(panorama = panel) }, service::indicators)
                loadCot(model.value.cot.query.range, force)
            }
        }
    }

    fun loadTemperatureHistory(range: MacroRange, force: Boolean = false) {
        historyRequest = requestHistory(
            MacroQuery(range), force, historyRequest,
            MacroUiState::history, { state, result -> state.copy(history = result) },
        ) { service.temperatureHistory(range) }
    }

    fun loadTreasury(range: MacroRange, force: Boolean = false) {
        treasuryRequest = requestHistory(
            MacroQuery(range), force, treasuryRequest,
            MacroUiState::treasury, { state, result -> state.copy(treasury = result) },
        ) { service.treasury(range) }
    }

    fun loadIndicator(seriesId: String, range: MacroRange, force: Boolean = false) {
        detailRequest = requestHistory(
            MacroQuery(range, seriesId), force, detailRequest,
            MacroUiState::detail, { state, result -> state.copy(detail = result) },
        ) { service.indicator(seriesId, range) }
    }

    fun loadCot(range: MacroRange, force: Boolean = false) {
        cotRequest = requestHistory(
            MacroQuery(range), force, cotRequest,
            MacroUiState::cot, { state, result -> state.copy(cot = result) },
        ) { service.goldCot(range) }
    }

    private fun <T> requestHistory(
        query: MacroQuery,
        force: Boolean,
        previousJob: Job?,
        read: (MacroUiState) -> MacroHistoryPanel<T>,
        write: (MacroUiState, MacroHistoryPanel<T>) -> MacroUiState,
        fetch: suspend () -> T,
    ): Job? {
        val current = read(model.value)
        if (query == current.query && (current.panel.loading || current.panel.result != null && !force)) return previousJob

        previousJob?.cancel()
        val previous = if (query == current.query) current.panel else MacroPanel()
        val loading = MacroHistoryPanel(query, previous.copy(loading = true, failed = false))
        model.update { write(it, loading) }
        return viewModelScope.launch {
            val result = fetchPanel(previous, fetch)
            model.update { if (read(it) === loading) write(it, MacroHistoryPanel(query, result)) else it }
        }
    }

    private fun <T> request(
        force: Boolean,
        read: (MacroUiState) -> MacroPanel<T>,
        write: (MacroUiState, MacroPanel<T>) -> MacroUiState,
        fetch: suspend () -> T,
    ) {
        val current = read(model.value)
        if (current.loading || current.result != null && !force) return
        model.update { write(it, current.copy(loading = true, failed = false)) }
        viewModelScope.launch {
            val result = fetchPanel(current, fetch)
            model.update { write(it, result) }
        }
    }

    private suspend fun <T> fetchPanel(previous: MacroPanel<T>, fetch: suspend () -> T): MacroPanel<T> = try {
        MacroPanel(result = fetch())
    } catch (canceled: CancellationException) {
        throw canceled
    } catch (_: Exception) {
        previous.copy(loading = false, failed = true)
    }
}
