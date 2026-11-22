package com.oryjk.sumly.features.holdings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors

internal enum class HoldingPortfolioPage(val title: String) {
    Overview("全部持仓收益"),
    Profit("盈亏来源"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HoldingPortfolioSheet(
    page: HoldingPortfolioPage,
    state: HoldingsState,
    records: List<HoldingRecord>,
    portfolio: GoldPortfolioReturn?,
    onOpenProfit: () -> Unit,
    onOpenRecord: (HoldingRecord) -> Unit,
    onDismiss: () -> Unit,
) {
    val hidden = state.snapshot.amountsHidden
    val quote = state.referencePrice
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = GoldColors.Background,
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.88f),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(page.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text(state.currentBook, style = MaterialTheme.typography.bodySmall, color = GoldColors.Muted)
                    }
                    TextButton(onClick = onDismiss) { Text("完成") }
                }
            }
            if (records.isEmpty()) {
                item { HoldingCard { Text("当前账本暂无持有记录") } }
            } else if (page == HoldingPortfolioPage.Overview) {
                item {
                    HoldingCard {
                        PortfolioMetric("现在卖预计到手 · 估算", portfolio?.proceeds, hidden, GoldColors.Gold)
                        TextButton(onClick = onOpenProfit) {
                            Text("真实盈亏 ${holdingMoney(portfolio?.profit, hidden, signed = true)} · 查看来源 ›")
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            PortfolioMetric("总投入", portfolio?.totalCost, hidden, modifier = Modifier.weight(1f))
                            PortfolioMetric("组合真实保本价 / g", portfolio?.breakEvenPrice, hidden, modifier = Modifier.weight(1f))
                        }
                    }
                }
                items(records, key = { it.id }) { record ->
                    HoldingRecordCard(record, quote, hidden, onClick = { onOpenRecord(record) })
                }
            } else {
                item { HoldingProfitCard(records, portfolio, quote, state.referenceBasis, hidden) }
            }
        }
    }
}

@Composable
private fun PortfolioMetric(
    label: String,
    value: Double?,
    hidden: Boolean,
    color: Color = GoldColors.Text,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
        Text(holdingMoney(value, hidden), color = color, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun HoldingProfitCard(
    records: List<HoldingRecord>,
    portfolio: GoldPortfolioReturn?,
    quote: Double?,
    basis: String,
    hidden: Boolean,
) {
    val breakdown = remember(records, quote) { GoldProfitBreakdown.estimate(records.map { it.input }, quote) }
    HoldingCard {
        if (breakdown == null) {
            Text("参考金价暂不可用，获取报价后显示盈亏来源。", color = GoldColors.Muted)
        } else {
            val profit = breakdown.profitCents / 100.0
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("真实盈亏", fontWeight = FontWeight.SemiBold)
                Text(holdingMoney(profit, hidden, signed = true), color = if (hidden) GoldColors.Text else gainColor(profit))
            }
            for (source in breakdown.sources) {
                val amount = source.cents / 100.0
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(source.kind.title, modifier = Modifier.weight(1f), color = GoldColors.Muted)
                    Text(holdingMoney(amount, hidden, signed = true), color = if (hidden) GoldColors.Text else gainColor(amount))
                }
            }
        }
        Text(
            "预计到手 ${holdingMoney(portfolio?.proceeds, hidden)} · 总投入 ${holdingMoney(portfolio?.totalCost, hidden)}",
            color = GoldColors.Muted,
            style = MaterialTheme.typography.bodySmall,
        )
        Text("按${basis}及每笔回收规则估算", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
    }
}
