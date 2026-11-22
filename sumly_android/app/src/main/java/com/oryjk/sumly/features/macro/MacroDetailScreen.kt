package com.oryjk.sumly.features.macro

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
internal fun MacroDetailScreen(
    viewModel: MacroViewModel,
    seriesId: String,
    summary: MacroMetric?,
    history: MacroHistoryPanel<MacroIndicatorDetail>,
    onClose: () -> Unit,
) {
    var range by rememberSaveable(seriesId) { mutableStateOf(MacroRange.FiveYears) }
    LaunchedEffect(viewModel, seriesId, range) { viewModel.loadIndicator(seriesId, range) }
    val panel = history.panel.takeIf { history.query == MacroQuery(range, seriesId) } ?: MacroPanel(loading = true)
    val detail = panel.result
    val metric = detail?.metric ?: summary

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回宏观全景") }
            Text(metric?.title ?: "指标详情", style = MaterialTheme.typography.titleMedium)
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            if (metric != null) {
                item {
                    MacroHistoryCard {
                        Text(metric.value.formatted(2, metric.unit), style = MaterialTheme.typography.headlineMedium, color = GoldColors.Gold)
                        metric.date?.let { Text("最新日期 $it", style = MaterialTheme.typography.labelSmall, color = GoldColors.Muted) }
                        detail?.note?.takeIf(String::isNotBlank)?.let { Text(it, color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall) }
                    }
                }
            }
            item {
                MacroHistoryCard {
                    Text("历史走势", style = MaterialTheme.typography.titleMedium)
                    MacroRanges(range, onSelect = { range = it })
                    PanelStatus(panel) { viewModel.loadIndicator(seriesId, range, force = true) }
                    if (detail != null) {
                        MacroHistoryChart(
                            if (detail.metric.unit.isBlank()) detail.metric.title else "${detail.metric.title}（${detail.metric.unit}）",
                            listOf(MacroChartSeries(detail.metric.title, detail.observations, GoldColors.Gold)),
                            detail.metric.unit,
                        )
                    }
                }
            }
            if (detail != null) {
                item {
                    MacroHistoryCard {
                        Text("近期变化", style = MaterialTheme.typography.titleMedium)
                        detail.changes.forEach { change ->
                            val value = change.value
                            val prefix = if (value != null && value > 0) "+" else ""
                            DetailRow(change.title, prefix + value.formatted(2, change.unit))
                        }
                    }
                }
                item {
                    MacroHistoryCard {
                        Text("多窗口历史分位", style = MaterialTheme.typography.titleMedium)
                        if (detail.percentiles.isEmpty()) {
                            Text("暂无足够历史观测", style = MaterialTheme.typography.bodySmall, color = GoldColors.Muted)
                        }
                        detail.percentiles.forEach { item ->
                            val title = MacroRange.entries.firstOrNull { it.query == item.window }?.title ?: item.window
                            DetailRow("$title · ${item.count} 点", item.percentile.formatted(1, "%"))
                        }
                    }
                }
                item {
                    MacroHistoryCard {
                        Text("指标档案", style = MaterialTheme.typography.titleMedium)
                        DetailRow("数据来源", detail.source)
                        DetailRow("更新频率", frequencyLabel(detail.frequency))
                        DetailRow("计量单位", detail.metric.unit)
                        DetailRow("黄金逻辑", relationLabel(detail.goldRelation))
                        DetailRow("同步状态", syncLabel(detail.syncStatus))
                        detail.lastSyncedAt?.let {
                            DetailRow("最近同步", it.atZone(ZoneId.systemDefault()).format(LocalDateTimeFormat))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = GoldColors.Muted)
        Text(value.ifBlank { "—" }, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
    }
}

private val LocalDateTimeFormat = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

private fun frequencyLabel(frequency: String): String = when (frequency.lowercase()) {
    "daily" -> "日频"
    "weekly" -> "周频"
    "monthly" -> "月频"
    "quarterly" -> "季频"
    "annual", "yearly" -> "年频"
    else -> frequency
}

private fun relationLabel(relation: String): String = when (relation.lowercase()) {
    "positive", "bullish", "same" -> "与金价同向"
    "negative", "inverse", "bearish" -> "与金价反向"
    "neutral", "mixed", "reference" -> "综合参考"
    else -> relation
}

private fun syncLabel(status: String): String = when (status.lowercase()) {
    "ok", "success", "synced" -> "数据正常"
    "error", "failed" -> "同步异常"
    "skipped" -> "已跳过（未配置数据源）"
    "pending", "" -> "待同步"
    else -> status
}
