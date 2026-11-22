package com.oryjk.sumly.features.market

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.holdings.HoldingCard
import com.oryjk.sumly.features.holdings.HoldingMarketPurchase
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MarketPurchaseMarkerSheet(
    resolved: ResolvedPurchaseMarker,
    basis: MarketBasis,
    zone: ZoneId,
    onDismiss: () -> Unit,
) {
    val marker = resolved.marker
    var expandedPurchase by remember(marker.date) { mutableStateOf<UUID?>(null) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = GoldColors.Background,
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("买入点位明细", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                TextButton(onClick = onDismiss) { Text("完成") }
            }
            LazyColumn(
                Modifier.fillMaxWidth().weight(1f, fill = false).padding(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item { PurchaseComparisonCard(resolved, basis) }
                if (marker.items.isNotEmpty()) {
                    item { Text("购入明细", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
                    items(marker.items, key = { it.id }) { item ->
                        PurchaseItemCard(item, resolved, zone, expandedPurchase == item.id) {
                            expandedPurchase = item.id.takeUnless { it == expandedPurchase }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PurchaseComparisonCard(resolved: ResolvedPurchaseMarker, basis: MarketBasis) {
    val marker = resolved.marker
    val anchorLabel = if (resolved.interpolated) "临近交易日参考" else "当日大盘参考价"
    val weight = marker.items.takeIf { it.isNotEmpty() }?.sumOf { it.grams }
    val quantity = if (weight == null) "${marker.count} 笔" else "${marker.count} 笔 · ${marketMoney(weight)} 克"
    HoldingCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(marker.date.toString(), color = GoldColors.Text, fontWeight = FontWeight.SemiBold)
            Text(quantity, color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val costLabel = if (marker.count > 1) "当日买入加权成本" else "你的买入综合成本"
                ComparisonValue(costLabel, marker.costCnyPerGram)
                val costs = marker.items.map { it.cnyPerGram }
                val low = costs.minOrNull()
                val high = costs.maxOrNull()
                if (low != null && high != null && high - low >= 0.01) {
                    DetailCaption("单笔 ¥${marketMoney(low)}–¥${marketMoney(high)}")
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ComparisonValue(anchorLabel, resolved.anchorPrice)
                DetailCaption(if (basis == MarketBasis.Domestic) "国内 Au99.99" else "国际伦敦金折算")
            }
        }
        PurchaseSpread(marker.costCnyPerGram, resolved)
        HorizontalDivider(color = GoldColors.Border)
        DetailCaption(
            if (resolved.interpolated) {
                "大盘参考价根据临近交易日行情估算。红点为计入工费与溢价后的实际买入综合单价。"
            } else {
                "红点为计入工费与溢价后的实际买入综合单价，虚线表示与当日参考价的差额。"
            },
        )
    }
}

@Composable
private fun ColumnScope.ComparisonValue(label: String, price: Double?) {
    DetailCaption(label)
    Text(
        price?.let { "¥${marketMoney(it)}/克" } ?: "—",
        color = GoldColors.GoldSoft,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
private fun PurchaseItemCard(
    item: HoldingMarketPurchase,
    resolved: ResolvedPurchaseMarker,
    zone: ZoneId,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    HoldingCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.displayName, fontWeight = FontWeight.SemiBold)
                DetailCaption("${marketMoney(item.grams)} 克 · 总投入 ¥${marketMoney(item.totalCost)}")
            }
            TextButton(onClick = onToggle, modifier = Modifier.widthIn(min = 64.dp)) {
                Text(if (expanded) "收起" else "详情")
            }
        }
        if (expanded) {
            HorizontalDivider(color = GoldColors.Border)
            Text("${item.assetType.title} · ${marketTime(item.timestamp, zone, "yyyy/MM/dd HH:mm")}")
            DetailCaption("购入单价 ¥${marketMoney(item.unitPrice)}/克 · 综合成本 ¥${marketMoney(item.cnyPerGram)}/克")
            if (item.laborFee > 0) DetailCaption("含工费 ¥${marketMoney(item.laborFee)}")
            if (item.note.isNotBlank()) DetailCaption(item.note)
            PurchaseSpread(item.cnyPerGram, resolved)
        }
    }
}

@Composable
private fun PurchaseSpread(unitCost: Double, resolved: ResolvedPurchaseMarker) {
    val anchor = resolved.anchorPrice?.takeIf { it.isFinite() && it > 0 } ?: return
    val difference = unitCost - anchor
    val percent = abs(difference / anchor * 100.0)
    if (!difference.isFinite() || !percent.isFinite()) return
    val reference = if (resolved.interpolated) "临近交易日" else "当日大盘"
    val (text, tint) = when {
        abs(difference) < 0.005 -> "与${reference}持平" to GoldColors.Muted
        difference > 0 -> "较${reference}多花 ¥${marketMoney(difference)}/克（${marketMoney(percent)}%）" to GoldColors.Down
        else -> "较${reference}省 ¥${marketMoney(-difference)}/克（${marketMoney(percent)}%）" to GoldColors.Up
    }
    Text(text, color = tint, style = MaterialTheme.typography.labelMedium)
}

@Composable
private fun DetailCaption(text: String) {
    Text(text, color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
}
