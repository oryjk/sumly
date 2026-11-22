package com.oryjk.sumly.features.holdings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import java.util.Locale

private data class ScenarioPreset(val title: String, val multiplier: Double?)

private val scenarioPresets = listOf(
    ScenarioPreset("-10%", 0.9), ScenarioPreset("-5%", 0.95), ScenarioPreset("当前", 1.0),
    ScenarioPreset("保本", null), ScenarioPreset("+5%", 1.05), ScenarioPreset("+10%", 1.1),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HoldingScenarioSheet(
    record: HoldingRecord,
    referencePrice: Double?,
    referenceBasis: String,
    hidden: Boolean,
    onDismiss: () -> Unit,
) {
    val currentQuote = GoldReturnCalculator.validPrice(referencePrice)
    val breakEven = remember(record.input) { GoldReturnCalculator.calculate(record.input, null)?.breakEvenPrice }
    val shownBreakEven = breakEven?.takeUnless { hidden }?.let(GoldReturnCalculator::validPrice)
    val initialPrice = currentQuote ?: shownBreakEven
    val upper = maxOf(1000.0, (currentQuote ?: 0.0) * 1.5, (shownBreakEven ?: 0.0) * 1.2)
        .coerceAtMost(1_000_000_000.0).toFloat()
    var priceText by rememberSaveable(record.id.toString(), hidden, referenceBasis) {
        mutableStateOf(initialPrice?.let(::scenarioPriceText).orEmpty())
    }
    val price = GoldReturnCalculator.validPrice(priceText.trim().toDoubleOrNull())
    val result = remember(record.input, price) { GoldReturnCalculator.calculate(record.input, price) }
    val distance = result?.priceDistance
    val percent = result?.profitPercent

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = GoldColors.Background,
    ) {
        Column(
            Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("情景测算", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = onDismiss) { Text("完成") }
            }
            Text("如果参考金价变成这个价格，这笔黄金会怎样？", color = GoldColors.Muted)
            Text(referenceBasis, color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
            OutlinedTextField(
                value = priceText,
                onValueChange = { priceText = it.take(30) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("假设参考金价（元/克）") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                isError = priceText.isNotBlank() && price == null,
                supportingText = if (priceText.isNotBlank() && price == null) {
                    { Text("请输入有效的正数金价。") }
                } else null,
            )
            Slider(
                value = (price ?: 1.0).coerceIn(1.0, upper.toDouble()).toFloat(),
                onValueChange = { priceText = scenarioPriceText(it.toDouble()) },
                valueRange = 1f..upper,
                modifier = Modifier.semantics { contentDescription = "假设参考金价" },
            )
            scenarioPresets.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { preset ->
                        val target = if (preset.multiplier == null) shownBreakEven else currentQuote?.times(preset.multiplier)
                        val formatted = GoldReturnCalculator.validPrice(target)?.let(::scenarioPriceText)
                        FilterChip(
                            selected = formatted != null && priceText == formatted,
                            onClick = { if (formatted != null) priceText = formatted },
                            enabled = formatted != null,
                            label = { Text(preset.title) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
            HoldingCard {
                Text("现在卖预计到手 · 情景估算", color = GoldColors.Muted)
                Text(
                    holdingMoney(result?.proceeds, hidden),
                    color = if (hidden) GoldColors.Muted else GoldColors.Gold,
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text("真实盈亏", color = GoldColors.Muted)
                Text(holdingMoney(result?.profit, hidden, signed = true), color = gainColor(result?.profit.takeUnless { hidden }))
                Text("真实收益率", color = GoldColors.Muted)
                Text(when {
                    hidden -> "••••"
                    percent == null -> "—"
                    else -> String.format(Locale.ROOT, "%+.2f%%", percent)
                })
                Text(
                    when {
                        hidden -> "保本距离 •••• 元/克"
                        distance == null -> "输入参考金价后显示保本距离"
                        distance >= 0 -> "已达到真实保本线 · ${holdingMoney(distance, false, " / g")}"
                        else -> "距离真实保本还差 ${holdingMoney(-distance, false, " / g")}"
                    },
                    color = if (hidden) GoldColors.Muted else GoldColors.GoldSoft,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Text(
                "情景计算按这笔持仓的纯度和回收规则估算。",
                color = GoldColors.Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

private fun scenarioPriceText(value: Double): String = String.format(Locale.ROOT, "%.2f", value)
