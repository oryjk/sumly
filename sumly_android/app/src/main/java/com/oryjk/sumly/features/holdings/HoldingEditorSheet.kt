package com.oryjk.sumly.features.holdings

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.market.MarketBasis
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun AddHoldingSheet(viewModel: HoldingsViewModel, onDismiss: () -> Unit) {
    HoldingEditorSheet(viewModel, onDismiss = onDismiss)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HoldingEditorSheet(
    viewModel: HoldingsViewModel,
    record: HoldingRecord? = null,
    initialDate: Instant? = null,
    initialBook: String? = null,
    onDismiss: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var receipt by remember(viewModel, record?.id) { mutableStateOf<HoldingReceiptSnapshot?>(null) }
    val openedRecord = remember(record?.id) { record }
    var detail by remember(record?.id) { mutableStateOf(record != null) }
    var autoPrice by remember(record?.id) { mutableStateOf(record == null) }
    var draft by remember(record?.id, initialDate, initialBook) {
        val initial = record?.let(HoldingDraft::from) ?: HoldingDraft(
            timestamp = initialDate ?: Instant.now(),
            bookName = initialBook ?: state.currentBook,
            unitPrice = state.referencePrice
                ?.takeIf { initialDate == null || initialDate.isToday() }
                ?.let(::priceFieldText).orEmpty(),
        ).selectAssetType(HoldingAssetType.Bean)
        mutableStateOf(initial)
    }
    val input = remember(draft) { draft.input() }
    val estimate = remember(input) { input?.let { GoldReturnCalculator.calculate(it, null) } }
    val day = draft.timestamp.atZone(ZoneId.systemDefault()).toLocalDate()
    val today = draft.timestamp.isToday()
    var todayReference by remember(day, state.marketBasis) {
        mutableStateOf(state.referencePrice.takeIf { today })
    }
    var historicalReference by remember(day, state.marketBasis) { mutableStateOf<Double?>(null) }
    var loadingReference by remember(day, state.marketBasis) { mutableStateOf(!today) }
    LaunchedEffect(day, state.marketBasis, state.referencePrice) {
        if (today && todayReference == null) todayReference = state.referencePrice
    }
    LaunchedEffect(day, state.marketBasis) {
        if (!today) {
            historicalReference = viewModel.historicalPurchasePrice(state.marketBasis, day)
            loadingReference = false
        }
    }
    val reference = if (today) todayReference else historicalReference
    LaunchedEffect(reference, autoPrice, draft.useCashTotal, state.marketBasis) {
        if (autoPrice && !draft.useCashTotal) {
            draft = draft.copy(unitPrice = reference?.let(::priceFieldText).orEmpty())
        }
    }
    val closeSheet = {
        if (!state.isSaving) {
            viewModel.dismissError()
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = closeSheet,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = GoldColors.Background,
    ) {
        val saved = receipt
        if (saved != null) {
            HoldingReceiptContent(saved, hidden = state.snapshot.amountsHidden, onDone = closeSheet)
            return@ModalBottomSheet
        }
        val focusManager = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        Column(Modifier.fillMaxWidth().imePadding()) {
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        if (record == null) "记一笔黄金" else "编辑持仓",
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    TextButton(onClick = closeSheet, enabled = !state.isSaving) { Text("取消") }
                }
                QuickAssetSelector(draft.assetType) { type ->
                    if (type != draft.assetType) draft = draft.selectAssetType(type, applyDefaults = record == null)
                }
                HoldingCard {
                    NumberField("购入克重", draft.grams) { draft = draft.copy(grams = it) }
                    if (record == null) {
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            listOf("1", "5", "10", "20", "50", "100").forEach { grams ->
                                FilterChip(
                                    selected = draft.grams == grams,
                                    onClick = { draft = draft.copy(grams = grams) },
                                    label = { Text("${grams}g") },
                                )
                            }
                        }
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        LinkedPriceField(
                            "单价（元/克）", if (autoPrice) "参考价" else "手动",
                            draft.unitPrice, !draft.useCashTotal, Modifier.weight(1f),
                        ) {
                            autoPrice = false
                            draft = draft.enterUnitPrice(it)
                        }
                        LinkedPriceField(
                            "总价（元）", if (draft.useCashTotal) "实付总价" else "自动估算",
                            if (draft.useCashTotal) draft.cashTotal else estimate?.totalCost?.let(::priceFieldText).orEmpty(),
                            draft.useCashTotal, Modifier.weight(1f),
                        ) {
                            autoPrice = false
                            draft = draft.enterCashTotal(it)
                        }
                    }
                    if (reference != null) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            val referenceLabel = when {
                                today -> "${state.marketBasis.label}实时金价"
                                state.marketBasis == MarketBasis.International -> "国际历史收盘 · 按当前汇率折算"
                                else -> "国内历史收盘"
                            }
                            Text(
                                "参考 · $referenceLabel ${priceFieldText(reference)} 元/克",
                                Modifier.weight(1f),
                                color = GoldColors.Muted,
                                style = MaterialTheme.typography.bodySmall,
                            )
                            if (!autoPrice || draft.useCashTotal) {
                                TextButton(onClick = {
                                    autoPrice = true
                                    draft = draft.enterUnitPrice(priceFieldText(reference))
                                }) { Text("恢复参考价") }
                            }
                        }
                    } else {
                        Text(
                            when {
                                loadingReference -> "正在查询所选日期的参考价…"
                                today -> "参考价暂未获取成功，可手动填写购入单价"
                                else -> "该日暂无参考价，请填写实际购入单价"
                            },
                            color = GoldColors.Muted,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    if (estimate != null) {
                        Text(
                            "预计真实保本金价 ${holdingMoney(estimate.breakEvenPrice, false, "/克")}",
                            color = GoldColors.Gold, style = MaterialTheme.typography.bodyMedium,
                        )
                    } else {
                        Text(
                            "选好克重并核对单价或总价，即时显示预计真实保本金价。",
                            color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
                HoldingCard {
                    TextButton(onClick = { detail = !detail }, modifier = Modifier.fillMaxWidth()) {
                        Text("补充细节 ${if (detail) "▴" else "▾"}")
                    }
                    if (detail) {
                        HoldingBookMenu(
                            draft.bookName, state.snapshot.books, onSelect = { draft = draft.copy(bookName = it) },
                        )
                        HoldingDateTimeFields("购入时间", draft.timestamp) { date ->
                            val selectedDay = date.atZone(ZoneId.systemDefault()).toLocalDate()
                            val price = if (autoPrice && selectedDay != day) "" else draft.unitPrice
                            draft = draft.copy(timestamp = date, unitPrice = price)
                        }
                        NumberField("纯度（%）", draft.purityPercent) { draft = draft.copy(purityPercent = it) }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(
                                selected = draft.laborPerGram,
                                onClick = { draft = draft.copy(laborPerGram = true) },
                                label = { Text("按克工费") },
                            )
                            FilterChip(
                                selected = !draft.laborPerGram,
                                onClick = { draft = draft.copy(laborPerGram = false) },
                                label = { Text("工费总额") },
                            )
                        }
                        val laborLabel = if (draft.laborPerGram) "工费（元/克）" else "工费总额（元）"
                        NumberField(laborLabel, draft.labor) { draft = draft.copy(labor = it) }
                        NumberField("其他费用（元）", draft.extraFee) { draft = draft.copy(extraFee = it) }
                        LabelField("品牌", draft.brand) { draft = draft.copy(brand = it) }
                        LabelField("购入渠道", draft.channel) { draft = draft.copy(channel = it) }
                        LabelField("备注", draft.note) { draft = draft.copy(note = it) }
                        Text("回收规则", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        NumberField("每克扣减（元）", draft.deduction) { draft = draft.copy(deduction = it) }
                        NumberField("折价比例（%）", draft.discountPercent) { draft = draft.copy(discountPercent = it) }
                        NumberField("固定费用（元）", draft.fixedFee) { draft = draft.copy(fixedFee = it) }
                    }
                }
                state.error?.let { HoldingError(it) }
            }
            Button(
                enabled = estimate != null && !state.isSaving && !state.isLoading && !state.loadFailed &&
                    (!autoPrice || draft.unitPrice == reference?.let(::priceFieldText)),
                onClick = {
                    focusManager.clearFocus()
                    keyboard?.hide()
                    viewModel.save(draft, openedRecord) { savedReceipt ->
                        if (savedReceipt == null) onDismiss() else receipt = savedReceipt
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            ) { Text(if (state.isSaving) "保存中" else if (record == null) "确认入库" else "保存修改") }
        }
    }
}

@Composable
private fun QuickAssetSelector(selected: HoldingAssetType, onSelect: (HoldingAssetType) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("选择形态", Modifier.weight(1f), color = GoldColors.Muted, style = MaterialTheme.typography.labelMedium)
            TextButton(onClick = { onSelect(HoldingAssetType.Other) }) {
                Text("其他", color = if (selected == HoldingAssetType.Other) GoldColors.Gold else GoldColors.Muted)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            HoldingAssetType.entries.filterNot { it == HoldingAssetType.Other }.forEach { type ->
                val active = selected == type
                val glyph = when (type) {
                    HoldingAssetType.Bean -> Icons.Filled.Circle
                    HoldingAssetType.Bar -> Icons.Filled.ViewAgenda
                    HoldingAssetType.Jewelry -> Icons.Filled.Diamond
                    HoldingAssetType.Accumulation, HoldingAssetType.Other -> Icons.Filled.AccountBalance
                }
                Surface(
                    modifier = Modifier.weight(1f)
                        .semantics { this.selected = active }
                        .clickable(role = Role.Button, onClick = { onSelect(type) }),
                    shape = RoundedCornerShape(14.dp),
                    color = if (active) GoldColors.SurfaceElevated else GoldColors.Surface,
                    border = BorderStroke(1.dp, if (active) GoldColors.Gold else GoldColors.Border),
                ) {
                    Column(
                        Modifier.padding(horizontal = 2.dp, vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Icon(glyph, contentDescription = null, Modifier.size(24.dp), tint = GoldColors.Gold)
                        Text(type.title, color = GoldColors.Text, style = MaterialTheme.typography.labelMedium)
                        Text(
                            if (type == HoldingAssetType.Accumulation) "0工费" else "${type.purityPercent}%",
                            color = if (active) GoldColors.GoldSoft else GoldColors.Muted,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LinkedPriceField(
    title: String, badge: String, value: String, active: Boolean, modifier: Modifier, onChange: (String) -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(badge, color = if (active) GoldColors.GoldSoft else GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
        NumberField(title, value, onChange)
    }
}

private fun priceFieldText(value: Double): String = String.format(Locale.ROOT, "%.2f", value)

@Composable
internal fun HoldingDisposalDialog(
    viewModel: HoldingsViewModel,
    record: HoldingRecord,
    kind: HoldingDisposition,
    state: HoldingsState,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val openedRecord = remember(record.id) { record }
    var grams by remember { mutableStateOf(holdingNumber(openedRecord.input.grams)) }
    var amount by remember { mutableStateOf("") }
    var counterparty by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(Instant.now()) }
    val soldWeight = grams.trim().toDoubleOrNull()?.takeIf { it > 0 && it <= openedRecord.input.grams }
    val proceeds = if (kind == HoldingDisposition.Gift) 0.0 else {
        amount.trim().toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0.0 }
    }
    val close = {
        if (!state.isSaving) {
            viewModel.dismissError()
            onDismiss()
        }
    }
    AlertDialog(
        onDismissRequest = close,
        title = { Text("记录${kind.title}") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NumberField("${kind.title}克重（克）", grams) { grams = it }
                if (kind == HoldingDisposition.Sold) NumberField("实际到账（元）", amount) { amount = it }
                LabelField("对方或回收渠道", counterparty) { counterparty = it }
                HoldingDateTimeFields("${kind.title}时间", date) { date = it }
                state.error?.let { HoldingError(it) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = soldWeight != null && proceeds != null && !state.isSaving,
                onClick = {
                    val weight = soldWeight ?: return@TextButton
                    val actual = proceeds ?: return@TextButton
                    viewModel.dispose(openedRecord, weight, kind, actual, date, counterparty, onSaved)
                },
            ) { Text("确认${kind.title}") }
        },
        dismissButton = { TextButton(onClick = close, enabled = !state.isSaving) { Text("取消") } },
    )
}

@Composable
private fun NumberField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = onChange, modifier = Modifier.fillMaxWidth(),
        label = { Text(label) }, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
    )
}

@Composable
private fun LabelField(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(value, onChange, Modifier.fillMaxWidth(), label = { Text(label) }, singleLine = true)
}

@Composable
private fun HoldingDateTimeFields(label: String, time: Instant, onChange: (Instant) -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val local = time.atZone(zone)
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        TextButton(onClick = {
            val picker = DatePickerDialog(
                context,
                { _, year, month, day ->
                    val selected = LocalDate.of(year, month + 1, day)
                    val combined = selected.atTime(local.toLocalTime()).atZone(zone).toInstant()
                    onChange(minOf(combined, Instant.now()))
                },
                local.year, local.monthValue - 1, local.dayOfMonth,
            )
            picker.datePicker.maxDate = System.currentTimeMillis()
            picker.show()
        }) { Text("$label ${local.format(HoldingDateFormat)}") }
        TextButton(onClick = {
            TimePickerDialog(
                context,
                { _, hour, minute ->
                    onChange(local.toLocalDate().atTime(LocalTime.of(hour, minute)).atZone(zone).toInstant())
                },
                local.hour, local.minute, true,
            ).show()
        }) { Text(local.format(HoldingTimeFormat)) }
    }
}

private val HoldingTimeFormat = DateTimeFormatter.ofPattern("HH:mm")

private fun Instant.isToday(): Boolean =
    atZone(ZoneId.systemDefault()).toLocalDate() == LocalDate.now()
