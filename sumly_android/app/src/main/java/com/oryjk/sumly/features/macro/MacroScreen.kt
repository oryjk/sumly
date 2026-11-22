package com.oryjk.sumly.features.macro

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.design.GoldColors
import java.util.Locale

@Composable
internal fun TemperatureHomeCard(
    panel: MacroPanel<TemperatureSnapshot>,
    onOpen: (() -> Unit)? = null,
    onRetry: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = GoldColors.Surface,
        shape = MaterialTheme.shapes.extraLarge,
        border = BorderStroke(1.dp, GoldColors.Border),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("黄金温度计", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                if (onOpen != null) TextButton(onClick = onOpen) { Text("查看专题") }
            }
            panel.result?.let { TemperatureSummary(it) }
            PanelStatus(panel, onRetry)
        }
    }
}

@Composable
internal fun MacroScreen(viewModel: MacroViewModel, onClose: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(MacroTab.Temperature) }
    var selectedSeriesId by rememberSaveable { mutableStateOf<String?>(null) }
    val seriesId = selectedSeriesId
    if (seriesId != null) {
        val summary = state.panorama.result.orEmpty().asSequence().flatMap { it.metrics.asSequence() }
            .firstOrNull { it.seriesId == seriesId }
            ?: state.treasury.panel.result?.indicators?.metrics?.firstOrNull { it.seriesId == seriesId }
        val close = { selectedSeriesId = null }
        BackHandler(onBack = close)
        MacroDetailScreen(viewModel, seriesId, summary, state.detail, close)
        return
    }
    LaunchedEffect(viewModel, tab) {
        viewModel.load(tab)
        if (tab == MacroTab.Temperature) viewModel.loadTemperatureHistory(state.history.query.range)
    }
    val openIndicator: (String) -> Unit = { selectedSeriesId = it }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回行情") }
            Text("黄金温度与美国国债", style = MaterialTheme.typography.titleMedium)
        }
        TabRow(selectedTabIndex = tab.ordinal, containerColor = GoldColors.Background) {
            MacroTab.entries.forEach { destination ->
                Tab(selected = tab == destination, onClick = { tab = destination }, text = { Text(destination.title) })
            }
        }
        val retry = { viewModel.load(tab, force = true) }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            when (tab) {
                MacroTab.Temperature -> {
                    item { PanelStatus(state.temperature, retry) }
                    state.temperature.result?.let { report ->
                        item { TemperatureHomeCard(state.temperature.copy(loading = false, failed = false), onRetry = retry) }
                        if (report.factors.isNotEmpty()) {
                            item { Text("短期温度 · 五维拆解", style = MaterialTheme.typography.titleMedium) }
                            items(report.factors, key = { it.name }) { factor ->
                                Surface(color = GoldColors.Surface, shape = MaterialTheme.shapes.large) {
                                    Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text(factor.name)
                                            Text(factor.score.formatted(1), color = temperatureTint(factor.score))
                                        }
                                        if (factor.summary.isNotBlank()) Text(factor.summary, color = GoldColors.Muted)
                                    }
                                }
                            }
                        }
                    }
                    item {
                        val history = state.history
                        MacroHistoryCard {
                            Text("历史温度与金价", style = MaterialTheme.typography.titleMedium)
                            MacroRanges(history.query.range, temperature = true, onSelect = { viewModel.loadTemperatureHistory(it) })
                            PanelStatus(history.panel) { viewModel.loadTemperatureHistory(history.query.range, force = true) }
                            history.panel.result?.let {
                                MacroHistoryChart(
                                    "国际金价（美元/盎司）",
                                    listOf(MacroChartSeries("金价", it.gold, GoldColors.Gold)),
                                    "美元/盎司",
                                )
                                MacroHistoryChart(
                                    "黄金温度（0–100°）",
                                    listOf(MacroChartSeries("温度", it.temperature, GoldColors.TempFreezing)),
                                    "°",
                                    fixedRange = 0.0..100.0,
                                )
                            }
                        }
                    }
                }
                MacroTab.Treasury -> {
                    val treasury = state.treasury
                    treasury.panel.result?.let { item { MacroSectionCard(it.summary) } }
                    item {
                        MacroHistoryCard {
                            Text("美债与利率走势", style = MaterialTheme.typography.titleMedium)
                            MacroRanges(treasury.query.range, onSelect = { viewModel.loadTreasury(it) })
                            PanelStatus(treasury.panel, retry)
                            treasury.panel.result?.let {
                                MacroHistoryChart(
                                    "美债总规模（万亿美元）",
                                    listOf(MacroChartSeries("总规模", it.debt, GoldColors.Gold)),
                                    "万亿美元",
                                )
                                MacroHistoryChart(
                                    "10 年期实际与名义利率（%）",
                                    listOf(
                                        MacroChartSeries("实际利率", it.realYield, GoldColors.Gold),
                                        MacroChartSeries("名义利率", it.nominalYield, GoldColors.TempFreezing),
                                    ),
                                    "%",
                                )
                            }
                        }
                    }
                    treasury.panel.result?.indicators?.takeIf { it.metrics.isNotEmpty() }?.let {
                        item { MacroSectionCard(it, openIndicator) }
                    }
                }
                MacroTab.Panorama -> {
                    item { CotHistoryCard(state.cot, viewModel) }
                    item { PanelStatus(state.panorama, retry) }
                    items(state.panorama.result.orEmpty()) { MacroSectionCard(it, openIndicator) }
                }
            }
        }
    }
}

@Composable
private fun CotHistoryCard(history: MacroHistoryPanel<MacroCotReport>, viewModel: MacroViewModel) {
    MacroHistoryCard {
        Text("CFTC 黄金持仓（COT）", style = MaterialTheme.typography.titleMedium)
        MacroRanges(history.query.range, onSelect = { viewModel.loadCot(it) })
        PanelStatus(history.panel) { viewModel.loadCot(history.query.range, force = true) }
        val report = history.panel.result ?: return@MacroHistoryCard
        report.latest?.let { latest ->
            Text("最近一期 · ${latest.date}", color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
            Text("管理基金净头寸 ${latest.managedNet.formatted(0, "张")}")
            Text("互换交易商净头寸 ${latest.swapNet.formatted(0, "张")}")
            Text("总持仓 ${latest.openInterest.formatted(0, "张")}")
            latest.managedRatio?.let { Text("管理基金净头寸占比 ${it.formatted(1, "%")}", color = GoldColors.Muted) }
        }
        MacroHistoryChart(
            "黄金期货净头寸",
            listOf(
                MacroChartSeries("管理基金", report.points.map { MacroPoint(it.date, it.managedNet) }, GoldColors.Up),
                MacroChartSeries("互换交易商", report.points.map { MacroPoint(it.date, it.swapNet) }, GoldColors.TempFreezing),
            ),
            "张",
        )
    }
}

@Composable
private fun TemperatureSummary(report: TemperatureSnapshot) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("短期热度", color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
            Text(report.score.formatted(1, "°"), color = temperatureTint(report.score), style = MaterialTheme.typography.headlineMedium)
            Text(report.shortTermLabel, style = MaterialTheme.typography.bodyMedium)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("长期宏观", color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
            Text(report.longTermScore.formatted(0, "分"), color = GoldColors.GoldSoft, style = MaterialTheme.typography.headlineMedium)
            if (report.longTermScore != null) Text(report.longTermLabel, style = MaterialTheme.typography.bodyMedium)
        }
    }
    report.volatilityNote?.let { Text(it, color = GoldColors.GoldSoft, style = MaterialTheme.typography.bodySmall) }
    report.date?.let { Text("数据日期 $it", color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall) }
    if (report.degraded) Text("部分指标缺失", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun MacroSectionCard(section: MacroSection, onIndicator: ((String) -> Unit)? = null) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = GoldColors.Surface,
        shape = MaterialTheme.shapes.large,
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(section.title, color = GoldColors.GoldSoft, style = MaterialTheme.typography.titleMedium)
            section.metrics.forEachIndexed { index, metric ->
                if (index > 0) HorizontalDivider(color = GoldColors.Border)
                val seriesId = metric.seriesId
                val link = if (seriesId != null && onIndicator != null) Modifier.clickable { onIndicator(seriesId) } else Modifier
                Row(
                    Modifier.fillMaxWidth().then(link).padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(metric.title, style = MaterialTheme.typography.bodyMedium)
                        metric.date?.let { Text(it.toString(), color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall) }
                    }
                    Text(metric.value.formatted(2, metric.unit), color = GoldColors.Text, fontWeight = FontWeight.SemiBold)
                    if (seriesId != null && onIndicator != null) {
                        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = GoldColors.Muted)
                    }
                }
            }
        }
    }
}

@Composable
internal fun PanelStatus(panel: MacroPanel<*>, onRetry: () -> Unit) {
    if (panel.loading && panel.result == null) CircularProgressIndicator(color = GoldColors.Gold)
    if (panel.failed) {
        TextButton(onClick = onRetry) {
            Text(if (panel.result == null) "数据加载失败，点击重试" else "刷新失败，显示上次数据，点击重试")
        }
    }
}

internal fun Double?.formatted(precision: Int, unit: String = ""): String =
    this?.let { String.format(Locale.CHINA, "%.${precision}f", it) + unit } ?: "—"

private fun temperatureTint(value: Double?): Color = when {
    value == null -> GoldColors.Muted
    value < 20 -> GoldColors.TempFreezing
    value < 40 -> GoldColors.Down
    value < 60 -> GoldColors.GoldSoft
    value < 80 -> GoldColors.TempWarm
    else -> GoldColors.Up
}

@Composable
internal fun MacroHistoryCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), color = GoldColors.Surface, shape = MaterialTheme.shapes.large) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}
