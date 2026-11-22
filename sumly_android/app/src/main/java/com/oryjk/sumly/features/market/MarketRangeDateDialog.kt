package com.oryjk.sumly.features.market

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MarketRangeDateDialog(
    full: MarketTimeBounds,
    current: MarketTimeBounds,
    zone: ZoneId,
    onDismiss: () -> Unit,
    onApply: (LocalDate, LocalDate) -> Unit,
) {
    val from = full.start.atZone(zone).toLocalDate()
    val through = full.end.atZone(zone).toLocalDate()
    val validDates = remember(from, through) {
        object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis.asUtcDate() in from..through
            override fun isSelectableYear(year: Int): Boolean = year in from.year..through.year
        }
    }
    val selection = rememberDateRangePickerState(
        initialSelectedStartDateMillis = current.start.atZone(zone).toLocalDate().asUtcMillis(),
        initialSelectedEndDateMillis = current.end.atZone(zone).toLocalDate().asUtcMillis(),
        yearRange = from.year..through.year,
        selectableDates = validDates,
    )
    val start = selection.selectedStartDateMillis?.asUtcDate()
    val end = selection.selectedEndDateMillis?.asUtcDate()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth().padding(horizontal = 14.dp), shape = MaterialTheme.shapes.extraLarge) {
            Column(Modifier.heightIn(max = 580.dp)) {
                DateRangePicker(
                    state = selection,
                    modifier = Modifier.weight(1f),
                    title = { Text("选择日期范围", Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) },
                )
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 5.dp), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("取消") }
                    TextButton(
                        enabled = start != null && end != null && start <= end,
                        onClick = { if (start != null && end != null) onApply(start, end) },
                    ) { Text("应用") }
                }
            }
        }
    }
}

private fun LocalDate.asUtcMillis(): Long = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
private fun Long.asUtcDate(): LocalDate = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()
