package com.oryjk.sumly.features.holdings

import android.icu.util.Calendar
import android.icu.util.ChineseCalendar
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.design.GoldColors
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

private enum class CalendarPeriod(val title: String) { Day("日"), Month("月"), Year("年"), All("全部") }

@Composable
fun HoldingsCalendarScreen(viewModel: HoldingsViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val today = LocalDate.now()
    val zone = ZoneId.systemDefault()
    var dateKey by rememberSaveable { mutableLongStateOf(today.toEpochDay()) }
    val selected = LocalDate.ofEpochDay(dateKey)
    var period by rememberSaveable { mutableStateOf(CalendarPeriod.Month) }
    var book by rememberSaveable { mutableStateOf<String?>(null) }
    var search by rememberSaveable { mutableStateOf("") }
    var showAdd by rememberSaveable { mutableStateOf(false) }
    val hidden = state.snapshot.amountsHidden
    val filteredRecords = remember(state.snapshot.records, book, search) {
        val keyword = search.trim()
        state.snapshot.records.filter { record ->
            (book == null || record.bookName == book) &&
                (keyword.isEmpty() || record.displayName.contains(keyword, ignoreCase = true) ||
                    record.note.contains(keyword, ignoreCase = true) ||
                    record.purchaseChannel.contains(keyword, ignoreCase = true) ||
                    record.counterparty.contains(keyword, ignoreCase = true))
        }
    }
    val events = remember(filteredRecords, zone) { HoldingCalendar.events(filteredRecords, zone) }
    val visible = remember(events, selected, period) {
        events.filter { event ->
            when (period) {
                CalendarPeriod.Day -> event.date == selected
                CalendarPeriod.Month -> YearMonth.from(event.date) == YearMonth.from(selected)
                CalendarPeriod.Year -> event.date.year == selected.year
                CalendarPeriod.All -> true
            }
        }
    }
    val eventKindsByDate = remember(events) {
        events.groupBy({ it.date }, { it.kind }).mapValues { (_, kinds) -> kinds.toSet() }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("日历", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text("攒金陪伴日历", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = { dateKey = today.toEpochDay(); period = CalendarPeriod.Day }) {
                    Text("今天")
                }
            }
            HoldingBookMenu(
                book ?: "全部账本", state.snapshot.books, onSelect = { book = it }, onSelectAll = { book = null },
            )
            OutlinedTextField(
                search, { search = it }, Modifier.fillMaxWidth(),
                label = { Text("搜索日历记录") }, singleLine = true,
            )
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CalendarPeriod.entries.forEach {
                    FilterChip(selected = period == it, onClick = { period = it }, label = { Text(it.title) })
                }
            }
        }
        if (state.isLoading) item { CircularProgressIndicator(color = GoldColors.Gold) }
        if (state.loadFailed) item {
            HoldingError("无法读取本机持仓")
            Button(onClick = viewModel::reload) { Text("重新读取") }
        }
        if (!state.isLoading && !state.loadFailed) {
            if (period != CalendarPeriod.All) item {
                val canMoveForward = when (period) {
                    CalendarPeriod.Year -> selected.year < today.year
                    else -> YearMonth.from(selected) < YearMonth.from(today)
                }
                HoldingCard {
                    Row(
                        Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(onClick = {
                            dateKey = when (period) {
                                CalendarPeriod.Year -> selected.minusYears(1)
                                else -> selected.minusMonths(1).withDayOfMonth(1)
                            }.toEpochDay()
                        }) { Text("‹", modifier = Modifier.semantics { contentDescription = "上一页" }) }
                        Text(
                            if (period == CalendarPeriod.Year) "${selected.year}年"
                            else "${selected.year}年${selected.monthValue}月",
                            style = MaterialTheme.typography.titleMedium,
                            color = GoldColors.Gold,
                        )
                        TextButton(
                            enabled = canMoveForward,
                            onClick = {
                                dateKey = minOf(
                                    when (period) {
                                        CalendarPeriod.Year -> selected.plusYears(1)
                                        else -> selected.plusMonths(1).withDayOfMonth(1)
                                    },
                                    today,
                                ).toEpochDay()
                            },
                        ) { Text("›", modifier = Modifier.semantics { contentDescription = "下一页" }) }
                    }
                    if (period == CalendarPeriod.Year) {
                        YearCells(selected.year, today, eventKindsByDate.keys) { month ->
                            dateKey = month.atDay(1).toEpochDay()
                            period = CalendarPeriod.Month
                        }
                    } else {
                        MonthCells(selected, today, zone, eventKindsByDate) { date ->
                            dateKey = date.toEpochDay()
                            period = CalendarPeriod.Day
                        }
                    }
                }
            }
            item {
                val title = if (period == CalendarPeriod.Day) selected.format(HoldingDateFormat) else "${period.title}记录"
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    TextButton(onClick = { viewModel.dismissError(); showAdd = true }) { Text("添加记录") }
                }
                CalendarTotals(visible, hidden)
            }
            if (visible.isEmpty()) item { HoldingCard { Text("此期间暂无记录", color = GoldColors.Muted) } }
            items(visible, key = { "${it.kind}:${it.id}" }) { event ->
                HoldingCalendarEventCard(event, hidden)
            }
        }
    }

    if (showAdd) {
        val time = if (selected == today || period == CalendarPeriod.All) Instant.now() else {
            selected.atTime(12, 0).atZone(zone).toInstant()
        }
        // Snapshot the initial time so a quote refresh does not reset an open editor.
        val initial = remember { time }
        HoldingEditorSheet(viewModel, initialDate = initial, initialBook = book) { showAdd = false }
    }
}

@Composable
private fun MonthCells(
    selected: LocalDate, today: LocalDate, zone: ZoneId,
    eventKindsByDate: Map<LocalDate, Set<HoldingEventKind>>,
    onDate: (LocalDate) -> Unit,
) {
    val month = YearMonth.from(selected)
    val start = month.atDay(1).minusDays(month.atDay(1).dayOfWeek.value.toLong() - 1)
    val lunarLabels = remember(month, zone) {
        val calendar = ChineseCalendar()
        (1..month.lengthOfMonth()).associate { day ->
            calendar.timeInMillis = month.atDay(day).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
            val lunarDay = calendar.get(Calendar.DAY_OF_MONTH)
            val text = if (lunarDay == 1) {
                val leap = if (calendar.get(Calendar.IS_LEAP_MONTH) == 1) "闰" else ""
                "$leap${LunarMonths[calendar.get(Calendar.MONTH)]}月"
            } else {
                LunarDays.getOrNull(lunarDay - 1).orEmpty()
            }
            day to text
        }
    }
    Row(Modifier.fillMaxWidth()) {
        listOf("一", "二", "三", "四", "五", "六", "日").forEach { weekday ->
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(weekday, color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
            }
        }
    }
    repeat(6) { week ->
        val weekStart = start.plusDays((week * 7).toLong())
        if (weekStart <= month.atEndOfMonth()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                repeat(7) { index ->
                    val day = weekStart.plusDays(index.toLong())
                    val inside = YearMonth.from(day) == month
                    if (inside) {
                        CalendarDayCell(
                            day, selected, today, lunarLabels[day.dayOfMonth].orEmpty(),
                            eventKindsByDate[day].orEmpty(), Modifier.weight(1f),
                        ) { onDate(day) }
                    } else {
                        Box(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun CalendarDayCell(
    day: LocalDate, selected: LocalDate, today: LocalDate, lunar: String,
    eventKinds: Set<HoldingEventKind>, modifier: Modifier, onClick: () -> Unit,
) {
    val border = if (day == selected) GoldColors.Gold else GoldColors.Border
    Surface(
        modifier = modifier.heightIn(min = 51.dp).clickable(enabled = day <= today, onClick = onClick)
            .semantics { contentDescription = day.format(HoldingDateFormat) },
        color = GoldColors.SurfaceElevated, shape = RoundedCornerShape(7.dp), border = BorderStroke(1.dp, border),
    ) {
        Column(
            Modifier.padding(vertical = 3.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                day.dayOfMonth.toString(), style = MaterialTheme.typography.labelMedium,
                color = if (day == selected) GoldColors.Gold else GoldColors.Text,
            )
            Text(lunar, style = MaterialTheme.typography.labelSmall, color = GoldColors.Muted, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                eventKinds.forEach { Box(Modifier.size(4.dp).background(eventColor(it), CircleShape)) }
            }
        }
    }
}

@Composable
private fun YearCells(year: Int, today: LocalDate, eventDays: Set<LocalDate>, onSelect: (YearMonth) -> Unit) {
    val eventMonths = eventDays.map { YearMonth.from(it) }.toSet()
    repeat(3) { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(4) { index ->
                val month = YearMonth.of(year, row * 4 + index + 1)
                TextButton(
                    enabled = month <= YearMonth.from(today), onClick = { onSelect(month) },
                    modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 2.dp, vertical = 8.dp),
                ) {
                    Text("${month.monthValue}月", color = if (month in eventMonths) GoldColors.Gold else GoldColors.Muted)
                }
            }
        }
    }
}

@Composable
private fun CalendarTotals(events: List<HoldingEvent>, hidden: Boolean) {
    val purchase = events.filter { it.kind == HoldingEventKind.Purchase }
    val sales = events.filter { it.kind == HoldingEventKind.Sale }
    HoldingCard {
        Text("购入 ${purchase.size} 笔 · ${holdingWeight(purchase.sumOf { it.grams }, hidden)}")
        Text(
            "总投入 ${holdingMoney(purchase.sumOf { it.amount }, hidden)} · 实收 ${holdingMoney(sales.sumOf { it.amount }, hidden)}",
            color = GoldColors.Muted,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

@Composable
private fun HoldingCalendarEventCard(event: HoldingEvent, hidden: Boolean) {
    HoldingCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f)) {
                Text(event.title, fontWeight = FontWeight.SemiBold)
                Text(
                    "${event.date.format(HoldingDateFormat)} · ${event.bookName}",
                    color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(event.kind.title, color = eventColor(event.kind), fontWeight = FontWeight.Medium)
                Text(
                    "${holdingWeight(event.grams, hidden)} · ${holdingMoney(event.amount, hidden)}",
                    color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}

private fun eventColor(kind: HoldingEventKind): Color = when (kind) {
    HoldingEventKind.Purchase -> GoldColors.Gold
    HoldingEventKind.Sale -> GoldColors.Up
    HoldingEventKind.Gift -> GoldColors.Down
}

private val LunarMonths = listOf("正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊")
private val LunarDays = listOf(
    "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
)
