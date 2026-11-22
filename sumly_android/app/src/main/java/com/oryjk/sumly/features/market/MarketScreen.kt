package com.oryjk.sumly.features.market

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.oryjk.sumly.design.GoldColors
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val quickRanges = listOf(MarketRange.Realtime, MarketRange.Month, MarketRange.Quarter, MarketRange.Year, MarketRange.FiveYears)

@Composable
fun MarketScreen(
    viewModel: MarketViewModel,
    temperature: Int? = null,
    onTemperature: (() -> Unit)? = null,
    onChanlun: (() -> Unit)? = null,
    holdingOverlay: MarketHoldingOverlay? = null,
    footer: @Composable () -> Unit = {},
) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle, viewModel) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { viewModel.pollCharts() }
    }
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val zone = viewModel.chartZone
    val points = remember(state, zone) { state.visiblePoints(zone) }
    var showingSources by remember { mutableStateOf(false) }
    var showHoldings by rememberSaveable { mutableStateOf(true) }
    var canReset by remember(state.basis, state.range) { mutableStateOf(false) }
    var resetRevision by remember { mutableIntStateOf(0) }
    Column(
        modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            MarketBasisPicker(state.basis, state.pendingBasis, viewModel::selectBasis)
            if (onTemperature != null) {
                val tint = when {
                    temperature == null -> GoldColors.GoldSoft
                    temperature < 20 -> GoldColors.TempFreezing
                    temperature < 40 -> GoldColors.Down
                    temperature < 60 -> GoldColors.GoldSoft
                    temperature < 80 -> GoldColors.TempWarm
                    else -> GoldColors.Up
                }
                MarketHeaderAction(
                    temperature?.let { "$it°" } ?: "温度", Icons.Default.Thermostat, tint,
                    onTemperature, Modifier.align(Alignment.CenterStart),
                )
            }
            if (onChanlun != null) {
                MarketHeaderAction("禅观", Icons.AutoMirrored.Filled.ShowChart, GoldColors.GoldSoft, onChanlun, Modifier.align(Alignment.CenterEnd))
            }
        }
        MarketQuoteHeader(state, zone, viewModel::refresh)
        MarketRangePicker(
            state = state,
            onRange = viewModel::selectRange,
            onScale = viewModel::selectScale,
            showHoldings = showHoldings,
            onToggleHoldings = { showHoldings = !showHoldings },
            canReset = canReset,
            onReset = { resetRevision++; canReset = false },
        )
        MarketPriceChart(
            state = state,
            observations = points,
            zone = zone,
            overlay = holdingOverlay?.takeIf { showHoldings },
            resetRevision = resetRevision,
            onZoomChanged = { canReset = it },
            onSources = { showingSources = true },
            onRetry = viewModel::refresh,
        )
        footer()
        state.quote?.takeIf { it.cnyPerGram != null }?.let { MarketQuoteDetails(state.basis, it) }
    }
    if (showingSources) MarketSourcesDialog(state.basis) { showingSources = false }
}

@Composable
private fun MarketBasisPicker(selected: MarketBasis, pending: MarketBasis?, onSelect: (MarketBasis) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(0.52f).height(44.dp).background(GoldColors.Surface, CircleShape).padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (basis in MarketBasis.entries) {
            val active = selected == basis
            Box(
                modifier = Modifier.weight(1f).fillMaxHeight().clip(CircleShape)
                    .background(if (active) GoldColors.Gold else Color.Transparent)
                    .selectable(selected = active, enabled = pending == null, role = Role.RadioButton, onClick = { onSelect(basis) }),
                contentAlignment = Alignment.Center,
            ) {
                if (pending == basis) CircularProgressIndicator(Modifier.size(13.dp), strokeWidth = 2.dp)
                else Text(basis.label, color = if (active) GoldColors.OnGold else GoldColors.Muted, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun MarketHeaderAction(label: String, icon: ImageVector, tint: Color, action: () -> Unit, modifier: Modifier) {
    Row(
        modifier = modifier.clip(CircleShape).background(GoldColors.Surface).border(1.dp, GoldColors.Border, CircleShape)
            .clickable(role = Role.Button, onClick = action).height(36.dp).padding(horizontal = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
        Text(label, color = tint, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun MarketQuoteHeader(state: MarketUiState, zone: ZoneId, onRetry: () -> Unit) {
    val quote = state.quote
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("黄金价格", color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
            Text(marketMoney(quote?.cnyPerGram), color = GoldColors.Gold, fontSize = 43.sp, fontWeight = FontWeight.Bold)
            Text("元/克", color = GoldColors.GoldSoft, modifier = Modifier.padding(bottom = 8.dp))
        }
        val change = quote?.changePerGram
        val percent = quote?.changePercent
        if (change != null && percent != null) {
            val tint = marketDirection(change)
            Text(
                "今日 ${marketSigned(change)} (${marketSigned(percent)}%)",
                modifier = Modifier.background(tint.copy(alpha = 0.12f), CircleShape).padding(horizontal = 11.dp, vertical = 4.dp),
                color = tint,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        val label = when {
            state.switchFailed -> "行情口径切换失败"
            state.quoteLoading && quote == null -> "正在获取行情…"
            state.quoteFailed && quote == null -> "行情加载失败，点击重试"
            state.quoteFailed -> "刷新失败，显示上次行情 · 点击重试"
            quote?.cnyPerGram == null -> "人民币报价暂不可用 · 点击重试"
            else -> "最近报价 ${marketTime(quote.asOf, zone, "M月d日 HH:mm")}"
        }
        if (state.quoteFailed || !state.quoteLoading && quote?.cnyPerGram == null) {
            TextButton(onClick = onRetry) { Text(label) }
        } else {
            Text(label, color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun MarketRangePicker(
    state: MarketUiState,
    onRange: (MarketRange) -> Unit,
    onScale: (ChartScale) -> Unit,
    showHoldings: Boolean,
    onToggleHoldings: () -> Unit,
    canReset: Boolean,
    onReset: () -> Unit,
) {
    val enabled = state.pendingBasis == null
    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (range in quickRanges) {
                MarketPill(range.label, state.range == range, enabled, modifier = Modifier.weight(1f)) { onRange(range) }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().clip(CircleShape).background(GoldColors.Surface)
                .border(1.dp, GoldColors.Border, CircleShape).padding(3.dp),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            var expanded by remember { mutableStateOf(false) }
            Box(Modifier.weight(1f)) {
                val alternate = state.range.takeUnless { it in quickRanges }
                MarketPill(
                    alternate?.labelFor(state.basis) ?: "更多区间", alternate != null, enabled,
                    modifier = Modifier.fillMaxWidth(), icon = Icons.Default.KeyboardArrowDown, compact = true,
                ) { expanded = true }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    for (range in MarketRange.entries) {
                        DropdownMenuItem(text = { Text(range.labelFor(state.basis)) }, onClick = {
                            expanded = false
                            onRange(range)
                        })
                    }
                }
            }
            Row(Modifier.background(GoldColors.Background, CircleShape)) {
                for (scale in ChartScale.entries) MarketPill(scale.label, state.scale == scale, enabled, compact = true) { onScale(scale) }
            }
            MarketPill("持仓", showHoldings, enabled, icon = Icons.Default.CheckCircle, compact = true, onClick = onToggleHoldings)
            MarketPill("复位", false, canReset, icon = Icons.Default.RestartAlt, compact = true, onClick = onReset)
        }
    }
}

@Composable
private fun MarketPill(
    label: String,
    selected: Boolean,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    compact: Boolean = false,
    onClick: () -> Unit,
) {
    val tint = if (selected) GoldColors.OnGold else if (enabled) GoldColors.Muted else GoldColors.Faint
    Row(
        modifier = modifier.clip(CircleShape)
            .background(if (selected) GoldColors.Gold else if (compact) Color.Transparent else GoldColors.Surface)
            .border(1.dp, if (selected || compact) Color.Transparent else GoldColors.Border, CircleShape)
            .selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .height(if (compact) 31.dp else 36.dp).padding(horizontal = if (compact) 7.dp else 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
    ) {
        if (icon != null && icon != Icons.Default.KeyboardArrowDown) Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(12.dp))
        Text(label, color = tint, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
            style = MaterialTheme.typography.labelMedium, maxLines = 1, softWrap = false)
        if (icon == Icons.Default.KeyboardArrowDown) Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(13.dp))
    }
}

@Composable
private fun MarketQuoteDetails(basis: MarketBasis, quote: MarketQuote) {
    Surface(
        modifier = Modifier.fillMaxWidth().border(1.dp, GoldColors.Border, MaterialTheme.shapes.extraLarge),
        shape = MaterialTheme.shapes.extraLarge,
        color = GoldColors.Surface,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("行情概览", color = GoldColors.Text, style = MaterialTheme.typography.titleSmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf("开盘" to quote.open, "最高" to quote.high, "最低" to quote.low, "昨收" to quote.previousClose)
                    .forEach { (label, value) ->
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(label, color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
                            Text(marketMoney(quote.inCnyPerGram(value)), color = GoldColors.Text, style = MaterialTheme.typography.labelMedium)
                        }
                    }
            }
            if (basis == MarketBasis.International) {
                Text(
                    "伦敦金现货 ${marketMoney(quote.price)} 美元/盎司 · 汇率 ${marketMoney(quote.usdCny)}",
                    color = GoldColors.Muted,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@Composable
private fun MarketSourcesDialog(basis: MarketBasis, dismiss: () -> Unit) {
    val details = when (basis) {
        MarketBasis.Domestic -> "国内 Au99.99 以人民币/克报价。历史日线来自上海黄金交易所，截至昨天的可用交易日。"
        MarketBasis.International -> "伦敦金实时走势沿用采样时的人民币换算，历史走势按最新汇率折算。1900–2015 年为 USGS 年度均价参考，2016 年起为交易日日线。"
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("行情数据说明") },
        text = { Text("$details\n\n实时走势显示最近交易时段的实际报价。仅有滚动数据时显示最近可用的报价，休市和缺少报价的区间留空。") },
        confirmButton = { TextButton(onClick = dismiss) { Text("完成") } },
    )
}

internal fun marketMoney(value: Double?): String = value?.let { String.format(Locale.CHINA, "%.2f", it) } ?: "—"

internal fun marketSigned(value: Double): String = String.format(Locale.CHINA, "%+.2f", value)

internal fun marketTime(time: java.time.Instant, zone: ZoneId, pattern: String): String =
    DateTimeFormatter.ofPattern(pattern, Locale.CHINA).withZone(zone).format(time)

internal fun marketDirection(change: Double): Color = when {
    change > 0 -> GoldColors.Up
    change < 0 -> GoldColors.Down
    else -> GoldColors.Muted
}
