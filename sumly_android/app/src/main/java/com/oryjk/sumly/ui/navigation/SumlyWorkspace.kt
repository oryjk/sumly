package com.oryjk.sumly.ui.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.oryjk.sumly.bootstrap.AccountWorkspace
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.account.AccountHoldingsUi
import com.oryjk.sumly.features.account.AccountIdentity
import com.oryjk.sumly.features.account.AccountScreen
import com.oryjk.sumly.features.account.AccountViewModel
import com.oryjk.sumly.features.holdings.AddHoldingSheet
import com.oryjk.sumly.features.holdings.HoldingMarketOverlay
import com.oryjk.sumly.features.holdings.HoldingsCalendarScreen
import com.oryjk.sumly.features.holdings.HoldingsScreen
import com.oryjk.sumly.features.holdings.HoldingsStore
import com.oryjk.sumly.features.holdings.HoldingsViewModel
import com.oryjk.sumly.features.holdings.alerts.HoldingAlertsMonitor
import com.oryjk.sumly.features.holdings.cloud.HoldingsConflictChoice
import com.oryjk.sumly.features.macro.MacroScreen
import com.oryjk.sumly.features.macro.MacroTab
import com.oryjk.sumly.features.macro.MacroViewModel
import com.oryjk.sumly.features.macro.TemperatureHomeCard
import com.oryjk.sumly.features.market.MarketHoldingOverlay
import com.oryjk.sumly.features.market.MarketPurchaseMarker
import com.oryjk.sumly.features.market.MarketScreen
import com.oryjk.sumly.features.market.MarketViewModel
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
internal fun SumlyWorkspace(
    market: MarketViewModel,
    guestHoldings: HoldingsViewModel,
    account: AccountViewModel,
    macro: MacroViewModel,
    guestStore: HoldingsStore,
    openAccount: (AccountIdentity) -> AccountWorkspace,
    chanlun: @Composable (onClose: () -> Unit, onSignIn: () -> Unit) -> Unit,
) {
    val session by account.session.state.collectAsStateWithLifecycle()
    val identity = session.identity
    val workspace = remember(account, identity) { identity?.let(openAccount) }
    val owner = remember(workspace) { workspace?.let { AccountWorkspaceOwner() } }
    DisposableEffect(owner) { onDispose { owner?.viewModelStore?.clear() } }
    val holdings = if (workspace != null && owner != null) {
        val factory = remember(workspace, market) {
            viewModelFactory {
                initializer {
                    HoldingsViewModel(
                        workspace.store,
                        snapshots = workspace.store.snapshots,
                        historicalPrice = market::historicalPurchasePrice,
                    )
                }
            }
        }
        viewModel<HoldingsViewModel>(viewModelStoreOwner = owner, factory = factory)
    } else {
        guestHoldings
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val context = LocalContext.current.applicationContext
    val alerts = remember(context, identity?.userId) {
        HoldingAlertsMonitor(context, identity?.userId?.let { "user-$it" } ?: "guest")
    }
    var previousAlerts by remember { mutableStateOf<HoldingAlertsMonitor?>(null) }
    LaunchedEffect(alerts) {
        previousAlerts?.clearNotifications()
        previousAlerts = alerts
    }
    LaunchedEffect(lifecycle, alerts, holdings, identity, session.restoring, market) {
        if (!session.restoring) lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                val state = holdings.state.value
                if (!state.isLoading && !state.loadFailed) {
                    alerts.check(state.snapshot, market::quoteForAlerts) {
                        val active = account.session.state.value
                        !active.restoring && active.identity == identity && holdings.state.value.snapshot == state.snapshot
                    }
                }
                delay(15_000L)
            }
        }
    }
    val guestState by guestHoldings.state.collectAsStateWithLifecycle()
    val accountHoldings = if (workspace == null) null else key(identity) {
        AccountHoldingsControls(workspace, guestStore, guestState.snapshot.records.size)
    }
    LaunchedEffect(workspace, lifecycle) {
        if (workspace != null) lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { workspace.sync.run() }
    }

    var selection by rememberSaveable { mutableStateOf(SumlyTab.Market) }
    var showingAdd by rememberSaveable(identity?.userId, identity?.generation) { mutableStateOf(false) }
    var showingMacro by rememberSaveable { mutableStateOf(false) }
    var showingChanlun by rememberSaveable { mutableStateOf(false) }
    val sharedScreenState = rememberSaveableStateHolder()
    val ledgerScreenState = key(identity?.userId, identity?.generation) { rememberSaveableStateHolder() }
    val marketState by market.uiState.collectAsStateWithLifecycle()
    val holdingsState = key(holdings) { holdings.state.collectAsStateWithLifecycle().value }
    val macroState by macro.state.collectAsStateWithLifecycle()
    val overlay = remember(session.restoring, holdingsState.snapshot) {
        if (session.restoring) null else HoldingMarketOverlay.from(holdingsState.snapshot)?.let { item ->
            MarketHoldingOverlay(item.breakEven, item.markers.map { marker ->
                MarketPurchaseMarker(marker.id, marker.cnyPerGram, marker.count, marker.items)
            })
        }
    }
    LaunchedEffect(macro) { macro.load(MacroTab.Temperature) }

    LaunchedEffect(lifecycle, market) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { market.pollQuotes() }
    }
    LaunchedEffect(holdings, marketState.basis, marketState.quote) {
        holdings.setReferencePrice(
            price = marketState.quote?.cnyPerGram,
            basis = marketState.basis,
            previousPrice = marketState.quote?.previousCloseCnyPerGram,
        )
    }

    BackHandler(enabled = !showingAdd && (showingChanlun || showingMacro || selection != SumlyTab.Market)) {
        when {
            showingChanlun -> showingChanlun = false
            selection == SumlyTab.Market && showingMacro -> showingMacro = false
            else -> selection = SumlyTab.Market
        }
    }

    if (showingChanlun) {
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            chanlun({ showingChanlun = false }) {
                showingChanlun = false
                selection = SumlyTab.Account
                account.openSignIn()
            }
        }
        return
    }

    Column(
        modifier = Modifier.fillMaxSize()
            .background(GoldColors.Background)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)),
    ) {
        Box(Modifier.weight(1f)) {
            val screenState = when (selection) {
                SumlyTab.Holdings, SumlyTab.Calendar -> ledgerScreenState
                SumlyTab.Market, SumlyTab.Account -> sharedScreenState
            }
            screenState.SaveableStateProvider(selection.name) {
                when (selection) {
                    SumlyTab.Market -> if (showingMacro) {
                        MacroScreen(macro, onClose = { showingMacro = false })
                    } else {
                        screenState.SaveableStateProvider("market.panel") {
                            MarketScreen(
                                viewModel = market,
                                temperature = macroState.temperature.result?.badge,
                                onTemperature = { showingMacro = true },
                                onChanlun = { showingChanlun = true },
                                holdingOverlay = overlay,
                            ) {
                                TemperatureHomeCard(
                                    macroState.temperature,
                                    onOpen = { showingMacro = true },
                                    onRetry = { macro.load(MacroTab.Temperature, force = true) },
                                )
                            }
                        }
                    }
                    SumlyTab.Holdings -> if (session.restoring) OpeningHoldings() else HoldingsScreen(holdings, accountWorkspace = workspace != null)
                    SumlyTab.Calendar -> if (session.restoring) OpeningHoldings() else HoldingsCalendarScreen(holdings)
                    SumlyTab.Account -> AccountScreen(
                        account,
                        holdingsSync = accountHoldings,
                        onOpenChanlun = { showingChanlun = true },
                        onClearMarketCache = market::clearCache,
                    )
                }
            }
        }
        GoldFloatingTabBar(selection, onSelect = { selection = it }, onAdd = { if (!session.restoring) showingAdd = true })
    }

    if (showingAdd && !session.restoring) {
        AddHoldingSheet(holdings, onDismiss = { showingAdd = false })
    }
}

private class AccountWorkspaceOwner : ViewModelStoreOwner {
    override val viewModelStore = ViewModelStore()
}

@Composable
private fun OpeningHoldings() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(color = GoldColors.Gold)
    }
}

@Composable
private fun AccountHoldingsControls(workspace: AccountWorkspace, guestStore: HoldingsStore, guestCount: Int): AccountHoldingsUi {
    val scope = rememberCoroutineScope()
    val sync by workspace.sync.state.collectAsStateWithLifecycle()
    val hasChanges by workspace.store.hasLocalChanges.collectAsStateWithLifecycle()
    val time = sync.lastSyncedAt?.let { DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault()).format(it) }
    val status = when {
        sync.isSyncing -> "正在同步云端…"
        sync.conflictCount > 0 -> "${sync.conflictCount} 条记录在不同设备上都有修改。"
        sync.notice != null -> sync.notice.orEmpty()
        hasChanges -> "更改已保存在本机，等待同步。"
        time != null -> "已同步 · $time"
        else -> "已开启云同步，本机缓存支持离线记录。"
    }
    return AccountHoldingsUi(
        status = status,
        isSyncing = sync.isSyncing,
        guestRecordCount = guestCount,
        conflictCount = sync.conflictCount,
        conflictToken = sync.conflictToken,
        onSync = { scope.launch { workspace.sync.sync() } },
        onImportGuest = { scope.launch { workspace.sync.importGuestRecords(guestStore) } },
        onKeepLocal = { token -> scope.launch { workspace.sync.resolveConflict(token, HoldingsConflictChoice.Local) } },
        onUseRemote = { token -> scope.launch { workspace.sync.resolveConflict(token, HoldingsConflictChoice.Cloud) } },
    )
}
