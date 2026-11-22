package com.oryjk.sumly.features.holdings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.holdings.alerts.HoldingAlertsDialog
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun HoldingsScreen(viewModel: HoldingsViewModel, accountWorkspace: Boolean = false) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val hidden = state.snapshot.amountsHidden
    var search by rememberSaveable { mutableStateOf("") }
    var filter by rememberSaveable { mutableStateOf(HoldingDisposition.Holding) }
    var showNewBook by rememberSaveable { mutableStateOf(false) }
    var showAdd by rememberSaveable { mutableStateOf(false) }
    var showEdit by rememberSaveable { mutableStateOf(false) }
    var portfolioPage by rememberSaveable { mutableStateOf<HoldingPortfolioPage?>(null) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    val currentRecords = remember(state.snapshot.records, state.currentBook) {
        state.snapshot.records.filter { it.bookName == state.currentBook }
    }
    val activeRecords = remember(currentRecords) {
        currentRecords.filter { it.disposition == HoldingDisposition.Holding }
    }
    val portfolio = remember(activeRecords, state.referencePrice, state.previousPrice) {
        GoldReturnCalculator.aggregate(
            activeRecords.map { it.input },
            state.referencePrice,
            state.previousPrice,
        )
    }
    val visible = remember(currentRecords, filter, search) {
        val keyword = search.trim()
        currentRecords.filter {
            it.disposition == filter && (keyword.isEmpty() || it.displayName.contains(keyword, ignoreCase = true) ||
                it.note.contains(keyword, ignoreCase = true) || it.purchaseChannel.contains(keyword, ignoreCase = true))
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Box(Modifier.weight(1f)) {
                    HoldingBookMenu(
                        state.currentBook, state.snapshot.books, onSelect = viewModel::selectBook,
                        onCreateBook = { viewModel.dismissError(); showNewBook = true },
                    )
                }
                OutlinedTextField(
                    search, { search = it }, Modifier.weight(1f),
                    placeholder = { Text("搜索") }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = "搜索品牌、渠道或备注") },
                    shape = RoundedCornerShape(50),
                )
            }
                Text(
                    if (accountWorkspace) "账户账本 · 支持离线记录" else "本机游客记录",
                    color = GoldColors.Muted,
                    style = MaterialTheme.typography.bodySmall,
                )
        }
        if (state.isLoading) item { CircularProgressIndicator(color = GoldColors.Gold) }
        if (state.loadFailed) item { Button(onClick = viewModel::reload) { Text("重新读取") } }
        state.error?.takeUnless { showAdd || showEdit || selectedId != null || showNewBook }?.let { error ->
            item { HoldingError(error) }
        }
        if (!state.isLoading && !state.loadFailed) {
            item {
                HoldingsPortfolioCard(
                    portfolio, state.referenceBasis, state.referencePrice, hidden,
                    canTogglePrivacy = !state.isSaving,
                    onTogglePrivacy = viewModel::togglePrivacy,
                    onAdd = { viewModel.dismissError(); showAdd = true },
                    hasActiveRecords = activeRecords.isNotEmpty(),
                    onOpenOverview = { portfolioPage = HoldingPortfolioPage.Overview },
                    onOpenProfit = { portfolioPage = HoldingPortfolioPage.Profit },
                )
            }
            item {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    HoldingDisposition.entries.forEach { kind ->
                        FilterChip(selected = filter == kind, onClick = { filter = kind }, label = { Text(kind.title) })
                    }
                }
            }
            if (visible.isEmpty()) {
                item {
                    HoldingCard {
                        Text(if (search.isBlank()) "暂无${filter.title}记录" else "没有找到匹配的记录")
                    }
                }
            }
            items(visible, key = { it.id.toString() }) { record ->
                HoldingRecordCard(record, state.referencePrice, hidden) {
                    viewModel.dismissError()
                    selectedId = record.id.toString()
                }
            }
        }
    }

    if (showNewBook) {
        NewBookDialog(viewModel, state) { showNewBook = false }
    }
    if (showAdd) AddHoldingSheet(viewModel) { showAdd = false }
    portfolioPage?.let { page ->
        HoldingPortfolioSheet(
            page, state, activeRecords, portfolio,
            onOpenProfit = { portfolioPage = HoldingPortfolioPage.Profit },
            onOpenRecord = {
                portfolioPage = null
                viewModel.dismissError()
                selectedId = it.id.toString()
            },
            onDismiss = { portfolioPage = null },
        )
    }

    val selected = currentRecords.firstOrNull { it.id.toString() == selectedId }
    if (selected != null) {
        if (showEdit) {
            HoldingEditorSheet(viewModel, record = selected) {
                showEdit = false
                selectedId = null
            }
        } else {
            HoldingDetailsDialog(
                viewModel, selected, state,
                onEdit = { showEdit = true },
                onDismiss = { selectedId = null },
            )
        }
    }
}

@Composable
private fun HoldingsPortfolioCard(
    portfolio: GoldPortfolioReturn?, basis: String, referencePrice: Double?, hidden: Boolean,
    canTogglePrivacy: Boolean, onTogglePrivacy: () -> Unit, onAdd: () -> Unit,
    hasActiveRecords: Boolean, onOpenOverview: () -> Unit, onOpenProfit: () -> Unit,
) {
    HoldingCard {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("现在卖预计到手", color = GoldColors.Text)
                Text("估算", color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
            }
            IconButton(onClick = onTogglePrivacy, enabled = canTogglePrivacy) {
                Icon(
                    if (hidden) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = if (hidden) "显示金额" else "隐藏金额",
                )
            }
        }
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .clickable(enabled = hasActiveRecords, role = Role.Button, onClickLabel = "查看全部持仓收益", onClick = onOpenOverview),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                holdingMoney(portfolio?.proceeds, hidden),
                modifier = Modifier.weight(1f),
                color = GoldColors.Gold,
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
            )
            if (hasActiveRecords) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
        val profitColor = if (hidden) GoldColors.Text else gainColor(portfolio?.profit)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .clickable(enabled = hasActiveRecords, role = Role.Button, onClickLabel = "查看盈亏来源", onClick = onOpenProfit),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "真实盈亏 ${holdingMoney(portfolio?.profit, hidden, signed = true)}",
                modifier = Modifier.weight(1f), color = profitColor,
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(holdingsPercent(portfolio?.profitPercent, hidden), color = profitColor)
            if (hasActiveRecords) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "总持有 ${holdingWeight(portfolio?.grams, hidden)}", color = GoldColors.Muted,
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                "总投入 ${holdingMoney(portfolio?.totalCost, hidden)}", color = GoldColors.Muted,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        portfolio?.breakEvenPrice?.let { breakEven ->
            val status = when {
                referencePrice == null -> "获取参考金价后显示保本距离"
                hidden -> "保本距离 •••• 元/克"
                referencePrice < breakEven -> "距离真实保本还差 ${holdingMoney(breakEven - referencePrice, false)} / g"
                else -> "已超过真实保本线 ${holdingMoney(referencePrice - breakEven, false)} / g"
            }
            Text(status, color = GoldColors.Gold, style = MaterialTheme.typography.titleSmall)
            Text(
                "当前参考 ${holdingMoney(referencePrice, hidden)} / g · 保本 ${holdingMoney(breakEven, hidden)} / g",
                color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
            )
        }
        portfolio?.todayChange?.let { change ->
            Text(
                "今日价格变化带来的持仓变化 ${holdingMoney(change, hidden, signed = true)}",
                color = if (hidden) GoldColors.Muted else gainColor(change),
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Text(
            if (referencePrice == null) "参考金价暂不可用，仍可录入和查看保本价" else "按${basis}及每笔回收规则估算",
            color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
        )
        Button(onClick = onAdd, modifier = Modifier.fillMaxWidth()) {
            Text(if (portfolio?.breakEvenPrice == null) "记第一笔黄金" else "记一笔")
        }
    }
}

@Composable
internal fun HoldingRecordCard(record: HoldingRecord, quote: Double?, hidden: Boolean, onClick: () -> Unit) {
    val result = remember(record, quote) { GoldReturnCalculator.calculate(record.input, quote) }
    val date = record.timestamp.atZone(ZoneId.systemDefault()).format(HoldingDateFormat)
    val held = record.disposition == HoldingDisposition.Holding
    HoldingCard(Modifier.clickable(onClick = onClick)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    record.displayName, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "$date · ${record.assetType.title}",
                    color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(holdingWeight(record.input.grams, hidden), fontWeight = FontWeight.SemiBold)
                Text(
                    holdingMoney(if (held) result?.proceeds else record.disposalAmount, hidden),
                    color = if (hidden) GoldColors.Muted else GoldColors.Gold,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

@Composable
private fun HoldingDetailsDialog(
    viewModel: HoldingsViewModel, record: HoldingRecord, state: HoldingsState,
    onEdit: () -> Unit, onDismiss: () -> Unit,
) {
    var showAlerts by remember(record.id) { mutableStateOf(false) }
    if (showAlerts) {
        HoldingAlertsDialog(
            record = record,
            basis = state.marketBasis,
            saving = state.isSaving,
            saveError = state.error,
            onDismiss = { viewModel.dismissError(); showAlerts = false },
            onSave = viewModel::saveAlerts,
        )
        return
    }
    var showScenario by remember(record.id, record.disposition) { mutableStateOf(false) }
    var disposal by remember { mutableStateOf<HoldingDisposition?>(null) }
    var showDelete by remember { mutableStateOf(false) }
    if (showDelete) {
        val openedRecord = remember(record.id) { record }
        AlertDialog(
            onDismissRequest = { if (!state.isSaving) showDelete = false },
            title = { Text("删除这条记录？") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("删除后，这条记录将从本机账本和日历中移除。")
                    state.error?.let { HoldingError(it) }
                }
            },
            confirmButton = {
                TextButton(enabled = !state.isSaving, onClick = { viewModel.delete(openedRecord, onDismiss) }) {
                    Text("删除", color = GoldColors.Up)
                }
            },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text("取消") } },
        )
        return
    }
    disposal?.let { kind ->
        HoldingDisposalDialog(viewModel, record, kind, state, onDismiss = { disposal = null }, onSaved = onDismiss)
        return
    }
    val hidden = state.snapshot.amountsHidden
    val result = remember(record, state.referencePrice) { GoldReturnCalculator.calculate(record.input, state.referencePrice) }
    val held = record.disposition == HoldingDisposition.Holding
    if (showScenario && held) {
        HoldingScenarioSheet(record, state.referencePrice, state.referenceBasis, hidden) { showScenario = false }
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(record.displayName) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${record.bookName} · ${record.disposition.title}", color = GoldColors.Muted)
                Text("克重 ${holdingWeight(record.input.grams, hidden)}")
                Text("购入成本 ${holdingMoney(record.input.totalCost, hidden)}")
                if (held) {
                    TextButton(onClick = { showScenario = true }) { Text("情景测算") }
                    Text("预计到手 ${holdingMoney(result?.proceeds, hidden)}")
                    Text("保本金价 ${holdingMoney(result?.breakEvenPrice, hidden, "/克")}")
                } else {
                    Text("实际到手 ${holdingMoney(record.disposalAmount, hidden)}")
                    Text("已实现盈亏 ${holdingMoney(record.disposalAmount - record.input.totalCost, hidden)}")
                }
                record.note.takeIf { it.isNotEmpty() }?.let { Text(it, color = GoldColors.Muted) }
                if (held) {
                    Row {
                        TextButton(onClick = { disposal = HoldingDisposition.Sold }) { Text("卖出") }
                        TextButton(onClick = { disposal = HoldingDisposition.Gift }) { Text("赠出") }
                    }
                    TextButton(onClick = { viewModel.dismissError(); showAlerts = true }) { Text("持仓提醒") }
                }
                TextButton(onClick = { viewModel.dismissError(); showDelete = true }) {
                    Text("删除记录", color = GoldColors.Up)
                }
            }
        },
        confirmButton = { TextButton(onClick = onEdit) { Text("编辑") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
    )
}

@Composable
private fun NewBookDialog(viewModel: HoldingsViewModel, state: HoldingsState, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    val exists = name.trim() in state.snapshot.books
    AlertDialog(
        onDismissRequest = { if (!state.isSaving) onDismiss() },
        title = { Text("新建账本") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.take(80) }, label = { Text("账本名称") }, singleLine = true)
                if (exists) HoldingError("此账本已存在")
                state.error?.let { HoldingError(it) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !state.isSaving && !state.isLoading && name.isNotBlank() && !exists,
                onClick = { viewModel.createBook(name, onDismiss) },
            ) { Text("保存") }
        },
        dismissButton = { TextButton(enabled = !state.isSaving, onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
internal fun HoldingBookMenu(
    current: String, books: List<String>, onSelect: (String) -> Unit, onSelectAll: (() -> Unit)? = null,
    onCreateBook: (() -> Unit)? = null,
) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        TextButton(onClick = { expanded = true }) {
            Text("$current ▾", maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            if (onSelectAll != null) {
                DropdownMenuItem(text = { Text("全部账本") }, onClick = { expanded = false; onSelectAll() })
            }
            books.forEach { book ->
                DropdownMenuItem(text = { Text(book) }, onClick = { expanded = false; onSelect(book) })
            }
            if (onCreateBook != null) {
                HorizontalDivider()
                DropdownMenuItem(text = { Text("新建账本") }, onClick = { expanded = false; onCreateBook() })
            }
        }
    }
}

@Composable
internal fun HoldingCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth().then(modifier),
        color = GoldColors.Surface,
        shape = RoundedCornerShape(20.dp),
        border = BorderStroke(1.dp, GoldColors.Border),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
internal fun HoldingError(message: String, style: TextStyle = MaterialTheme.typography.bodySmall) {
    Text(message, style = style, color = GoldColors.Up)
}

internal val HoldingDateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

internal fun holdingMoney(value: Double?, hidden: Boolean, suffix: String = "", signed: Boolean = false): String = when {
    hidden -> "••••"
    value == null -> "—"
    else -> "¥${String.format(Locale.CHINA, if (signed) "%+,.2f" else "%,.2f", value)}$suffix"
}

internal fun holdingWeight(value: Double?, hidden: Boolean): String = when {
    hidden -> "•••• 克"
    value == null -> "—"
    else -> "${String.format(Locale.CHINA, "%,.2f", value)} 克"
}

private fun holdingsPercent(value: Double?, hidden: Boolean): String = when {
    hidden -> "••••"
    value == null -> "—"
    else -> String.format(Locale.CHINA, "%+.2f%%", value)
}

internal fun gainColor(value: Double?) = when {
    value == null || value == 0.0 -> GoldColors.Text
    value > 0.0 -> GoldColors.Up
    else -> GoldColors.Down
}
