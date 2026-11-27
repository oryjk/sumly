package com.oryjk.sumly.features.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.design.GoldColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

data class AccountHoldingsUi(
    val status: String,
    val isSyncing: Boolean,
    val guestRecordCount: Int,
    val conflictCount: Int,
    val conflictToken: Long?,
    val onSync: () -> Unit,
    val onImportGuest: () -> Unit,
    val onKeepLocal: (Long) -> Unit,
    val onUseRemote: (Long) -> Unit,
)

@Stable
interface AccountHoldingsSource {
    @Composable
    fun collectUi(): AccountHoldingsUi
}

@Composable
internal fun AccountSettingsScreen(
    viewModel: AccountViewModel,
    session: AccountSessionState,
    actions: AccountActions,
    holdingsSync: AccountHoldingsUi?,
    holdingsSyncSource: AccountHoldingsSource? = null,
    onClose: () -> Unit,
    onClearMarketCache: (suspend () -> Unit)?,
) {
    val identity = session.identity
    val capabilities by viewModel.settingsCapabilities.collectAsStateWithLifecycle()
    LaunchedEffect(identity) { viewModel.loadSettingsCapabilities(identity) }
    val scope = rememberCoroutineScope()
    var clearingMarketCache by remember { mutableStateOf(false) }
    var marketCacheNotice by remember { mutableStateOf<String?>(null) }
    var marketCacheFailed by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            IconButton(onClick = onClose) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回", tint = GoldColors.GoldSoft)
            }
            Text("设置", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        }

        SettingsCard {
            Text(
                if (identity == null) "游客持仓" else "持仓同步",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            if (identity == null) {
                Notice("游客记录保存在此设备。")
            } else {
                HoldingsSyncSection(
                    identity = identity,
                    holdingsSync = holdingsSync,
                    holdingsSyncSource = holdingsSyncSource,
                    accountBusy = actions.busy,
                )
            }
        }
        if (identity != null) {
            SettingsCard {
                Text("记金账户", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                if (identity.provider == AccountProvider.Email && capabilities.googleClientId != null &&
                    session.user?.email?.let(AuthValidation::validEmail) == true
                ) {
                    AccountSettingRow(
                        "绑定 Google", Icons.Outlined.Link, enabled = !actions.busy,
                        onClick = viewModel::openGoogleLink,
                    )
                }
                if (identity.provider == AccountProvider.Google && capabilities.email &&
                    capabilities.googleClientId != null && session.user?.email == null
                ) {
                    AccountSettingRow(
                        "添加邮箱登录", Icons.Outlined.Email, enabled = !actions.busy,
                        onClick = viewModel::openEmailLink,
                    )
                }
                AccountSettingRow(
                    "退出登录", Icons.AutoMirrored.Outlined.Logout, enabled = !actions.busy,
                    onClick = viewModel::showLogoutConfirmation,
                )
                AccountSettingRow(
                    "注销账号", Icons.Outlined.DeleteOutline,
                    enabled = !actions.busy, tint = MaterialTheme.colorScheme.error,
                    onClick = viewModel::showDeleteConfirmation,
                )
            }
        }
        session.notice?.let { Notice(it) }
        actions.error?.let { Notice(it, isError = true) }
        actions.notice?.let { Notice(it) }
        if (onClearMarketCache != null) {
            SettingsCard {
                AccountSettingRow(
                    if (clearingMarketCache) "正在清除行情缓存…" else "清除行情缓存",
                    Icons.Outlined.DeleteOutline,
                    enabled = !clearingMarketCache,
                ) {
                    clearingMarketCache = true
                    marketCacheNotice = null
                    scope.launch {
                        try {
                            onClearMarketCache()
                            marketCacheFailed = false
                            marketCacheNotice = "行情缓存已清除。"
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            marketCacheFailed = true
                            marketCacheNotice = "行情缓存清除失败，请重试。"
                        } finally {
                            clearingMarketCache = false
                        }
                    }
                }
                marketCacheNotice?.let { Notice(it, isError = marketCacheFailed) }
            }
        }
    }
}

@Composable
private fun HoldingsSyncSection(
    identity: AccountIdentity,
    holdingsSync: AccountHoldingsUi?,
    holdingsSyncSource: AccountHoldingsSource?,
    accountBusy: Boolean,
) {
    val resolved = key(identity) { holdingsSyncSource?.collectUi() } ?: holdingsSync
    val status = resolved?.status?.ifBlank { "等待同步。" } ?: "当前无法读取同步状态。"
    Notice(status)
    if (resolved != null) {
        HoldingsSyncSettings(resolved, identity, accountBusy)
    }
}

@Composable
private fun HoldingsSyncSettings(sync: AccountHoldingsUi, identity: AccountIdentity, accountBusy: Boolean) {
    var confirmGuestImport by remember(identity) { mutableStateOf(false) }
    var conflictBeingConfirmed by remember(identity) { mutableStateOf<Long?>(null) }
    val enabled = !sync.isSyncing && !accountBusy
    AccountSettingRow(
        if (sync.isSyncing) "同步中…" else "立即同步", Icons.Outlined.Sync,
        enabled = enabled, onClick = sync.onSync,
    )
    if (sync.guestRecordCount > 0) {
        AccountSettingRow(
            "导入此设备的游客记录（${sync.guestRecordCount} 条）", Icons.Outlined.CloudUpload, enabled = enabled,
        ) { confirmGuestImport = true }
    }
    val conflictToken = sync.conflictToken
    if (sync.conflictCount > 0 && conflictToken != null) {
        AccountSettingRow("处理同步冲突（${sync.conflictCount} 条）", Icons.Outlined.Sync, enabled = enabled) {
            conflictBeingConfirmed = conflictToken
        }
    }
    if (confirmGuestImport && sync.guestRecordCount > 0) {
        AlertDialog(
            onDismissRequest = { confirmGuestImport = false },
            title = { Text("导入游客记录") },
            text = { Text("将此设备的 ${sync.guestRecordCount} 条游客记录导入当前记金账户，并随账户持仓同步。") },
            dismissButton = { TextButton(onClick = { confirmGuestImport = false }) { Text("取消") } },
            confirmButton = {
                Button(
                    onClick = {
                        confirmGuestImport = false
                        sync.onImportGuest()
                    },
                    enabled = enabled,
                ) { Text("确认导入") }
            },
        )
    }
    val confirming = conflictBeingConfirmed
    if (confirming != null && confirming == conflictToken && sync.conflictCount > 0) {
        AlertDialog(
            onDismissRequest = { conflictBeingConfirmed = null },
            title = { Text("处理同步冲突") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("本机与云端均修改了这些记录。选择要保留的版本，买入记录及其关联卖出将一起处理。")
                    TextButton(
                        onClick = {
                            conflictBeingConfirmed = null
                            sync.onKeepLocal(confirming)
                        },
                        enabled = enabled,
                    ) { Text("冲突记录保留本机版本") }
                    TextButton(
                        onClick = {
                            conflictBeingConfirmed = null
                            sync.onUseRemote(confirming)
                        },
                        enabled = enabled,
                    ) { Text("冲突记录使用云端版本") }
                }
            },
            confirmButton = { TextButton(onClick = { conflictBeingConfirmed = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun SettingsCard(content: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = GoldColors.Surface),
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) { content() }
    }
}

@Composable
internal fun AccountSettingRow(
    title: String,
    icon: ImageVector,
    enabled: Boolean = true,
    tint: Color = GoldColors.GoldSoft,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) tint else GoldColors.Muted)
        Text(title, color = if (enabled) MaterialTheme.colorScheme.onSurface else GoldColors.Muted, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = GoldColors.Muted)
    }
}
