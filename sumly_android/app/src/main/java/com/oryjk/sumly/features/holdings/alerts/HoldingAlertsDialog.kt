package com.oryjk.sumly.features.holdings.alerts

import android.Manifest
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.holdings.HoldingError
import com.oryjk.sumly.features.holdings.HoldingRecord
import com.oryjk.sumly.features.market.MarketBasis

@Composable
internal fun HoldingAlertsDialog(
    record: HoldingRecord,
    basis: MarketBasis,
    saving: Boolean,
    saveError: String?,
    onDismiss: () -> Unit,
    onSave: (HoldingRecord, List<HoldingAlert>, () -> Unit) -> Unit,
) {
    val context = LocalContext.current
    val expected = remember(record.id) { record }
    val selectedBasis = remember(record.id) { basis }
    var entries by remember(record.id) {
        mutableStateOf(HoldingAlertKind.entries.map { kind ->
            val alert = expected.alerts.firstOrNull { it.kind == kind }
                ?: HoldingAlert(kind = kind, threshold = kind.defaultThreshold, enabled = false, basis = selectedBasis)
            AlertDraft(alert, alert.threshold.toString().removeSuffix(".0"))
        })
    }
    var notice by remember { mutableStateOf<String?>(null) }
    var showSettings by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<List<HoldingAlert>?>(null) }
    val permissionNotice = {
        notice = "请在系统设置中允许记金的持仓提醒。"
        showSettings = true
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val requested = pending
        pending = null
        if (requested != null) {
            if (granted && HoldingAlertsMonitor.allowed(context)) onSave(expected, requested, onDismiss)
            else permissionNotice()
        }
    }
    val busy = saving || pending != null
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text("持仓提醒") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("使用${selectedBasis.label}参考金价。", color = GoldColors.Muted)
                entries.forEachIndexed { index, item ->
                    val update: (AlertDraft) -> Unit = { next ->
                        entries = entries.toMutableList().apply { set(index, next) }
                        notice = null
                        showSettings = false
                    }
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(item.alert.kind.title, Modifier.weight(1f))
                        Switch(item.alert.enabled, { update(item.copy(alert = item.alert.copy(enabled = it))) }, enabled = !busy)
                    }
                    val field = item.alert.kind.field
                    if (field != null && item.alert.enabled) {
                        OutlinedTextField(
                            item.input, { update(item.copy(input = it)) },
                            Modifier.fillMaxWidth(), enabled = !busy, singleLine = true,
                            label = { Text(field) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        )
                    }
                }
                Text(
                    "在记金前台获取新行情时检查。首次检查建立基线，从目标下方越过才会通知，同一提醒间隔至少 24 小时。",
                    color = GoldColors.Muted,
                    style = MaterialTheme.typography.bodySmall,
                )
                (notice ?: saveError)?.let { HoldingError(it) }
                if (showSettings) {
                    TextButton(onClick = {
                        context.startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }) { Text("打开通知设置") }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    notice = null
                    showSettings = false
                    val alerts = entries.mapNotNull { it.toAlert(selectedBasis) }
                    when {
                        alerts.size != entries.size -> notice = "请填写有效目标，参考金价应大于 0。"
                        alerts.none { it.enabled } || HoldingAlertsMonitor.allowed(context) -> onSave(expected, alerts, onDismiss)
                        !HoldingAlertsMonitor.canPost(context) -> {
                            pending = alerts
                            permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                        else -> permissionNotice()
                    }
                },
                enabled = !busy,
            ) { Text(if (saving) "正在保存…" else "保存提醒") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("取消") } },
    )
}

private data class AlertDraft(val alert: HoldingAlert, val input: String) {
    fun toAlert(basis: MarketBasis): HoldingAlert? {
        if (alert.kind == HoldingAlertKind.BreakEven) return alert.copy(threshold = 0.0, basis = basis)
        val value = input.trim().toDoubleOrNull()?.takeIf {
            it.isFinite() && it >= 0.0 && (alert.kind != HoldingAlertKind.Price || it > 0.0)
        }
        if (alert.enabled && value == null) return null
        return alert.copy(threshold = value ?: alert.threshold, basis = basis)
    }
}
