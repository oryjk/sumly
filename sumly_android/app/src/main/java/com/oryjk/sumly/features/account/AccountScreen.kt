package com.oryjk.sumly.features.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.R
import com.oryjk.sumly.design.GoldColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun AccountScreen(
    viewModel: AccountViewModel,
    holdingsSync: AccountHoldingsUi? = null,
    onOpenChanlun: (() -> Unit)? = null,
    onClearMarketCache: (suspend () -> Unit)? = null,
) {
    val session by viewModel.session.state.collectAsStateWithLifecycle()
    val form by viewModel.form.collectAsStateWithLifecycle()
    val actions by viewModel.actions.collectAsStateWithLifecycle()
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val picker: GoogleCredentialPicker = remember(context) {
        { clientId, nonce -> GoogleSignIn.pickCredential(context, clientId, nonce) }
    }
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    var linkError by remember { mutableStateOf<String?>(null) }

    DisposableEffect(viewModel) {
        onDispose {
            viewModel.dismissForm()
            viewModel.dismissGoogleLink()
            viewModel.dismissLogoutConfirmation()
            if (viewModel.actions.value.confirmDelete != null) viewModel.dismissDeleteConfirmation()
        }
    }
    BackHandler(enabled = settingsOpen) { settingsOpen = false }
    if (settingsOpen) {
        AccountSettingsScreen(
            viewModel = viewModel,
            session = session,
            actions = actions,
            holdingsSync = holdingsSync,
            onClose = { settingsOpen = false },
            onClearMarketCache = onClearMarketCache,
        )
    } else {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("我的", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text("记下每一克，积累每一天。", color = GoldColors.Muted)
                }
                IconButton(onClick = { settingsOpen = true }) {
                    Icon(Icons.Outlined.Settings, contentDescription = "设置", tint = GoldColors.GoldSoft)
                }
            }
            AccountProfileCard(session, viewModel::openSignIn, actions.busy)
            session.notice?.let { Notice(it) }
            actions.error?.let { Notice(it, isError = true) }
            Card(
                colors = CardDefaults.cardColors(containerColor = GoldColors.Surface),
                shape = RoundedCornerShape(24.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    if (onOpenChanlun != null) {
                        AccountSettingRow("禅观", Icons.AutoMirrored.Outlined.ShowChart, onClick = onOpenChanlun)
                    }
                    AccountSettingRow("隐私政策", Icons.Outlined.PrivacyTip) {
                        linkError = try {
                            uriHandler.openUri("https://oryjk.cn/sumly/privacy")
                            null
                        } catch (_: IllegalArgumentException) {
                            "无法打开浏览器，请访问 oryjk.cn/sumly/privacy。"
                        }
                    }
                    AccountSettingRow("联系支持", Icons.Outlined.Email) {
                        linkError = try {
                            uriHandler.openUri("mailto:oryjk@qq.com")
                            null
                        } catch (_: IllegalArgumentException) {
                            "无法打开邮件应用，支持邮箱为 oryjk@qq.com。"
                        }
                    }
                }
            }
            linkError?.let { Notice(it, isError = true) }
        }
    }

    if (actions.confirmLogout != null && actions.confirmLogout == session.identity) {
        AlertDialog(
            onDismissRequest = viewModel::dismissLogoutConfirmation,
            title = { Text("退出登录") },
            text = { Text("退出后显示此设备的游客记录。账户内未同步的修改保留在本机，重新登录后可继续同步。") },
            dismissButton = { TextButton(onClick = viewModel::dismissLogoutConfirmation) { Text("取消") } },
            confirmButton = { Button(onClick = viewModel::logout) { Text("退出登录") } },
        )
    }
    actions.confirmDelete?.takeIf { it.identity == session.identity }?.let { intent ->
        AlertDialog(
            onDismissRequest = viewModel::dismissDeleteConfirmation,
            title = { Text("注销 ${intent.maskedIdentifier}") },
            text = { Text("注销会永久删除该账号与云端账本、持仓。此设备的独立游客记录会保留。") },
            dismissButton = { TextButton(onClick = viewModel::dismissDeleteConfirmation) { Text("取消") } },
            confirmButton = {
                TextButton(onClick = viewModel::confirmAccountDeletion) {
                    Text("确认注销", color = MaterialTheme.colorScheme.error)
                }
            },
        )
    }
    actions.googleLink?.takeIf { it == session.identity }?.let {
        GoogleLinkDialog(actions, viewModel) { password ->
            scope.launch { viewModel.linkGoogle(password, picker) }
        }
    }
    form?.let {
        AuthenticationSheet(it, viewModel, onGoogle = {
            scope.launch { viewModel.signInWithGoogle(picker) }
        })
    }
}

@Composable
private fun AccountProfileCard(session: AccountSessionState, onSignIn: () -> Unit, busy: Boolean) {
    Card(
        colors = CardDefaults.cardColors(containerColor = GoldColors.Surface),
        shape = RoundedCornerShape(24.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val user = session.user
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(54.dp).background(GoldColors.Gold.copy(alpha = 0.12f), CircleShape),
                    contentAlignment = Alignment.Center) {
                    if (session.restoring) {
                        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Filled.Person, contentDescription = null, tint = GoldColors.Gold)
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val title = when {
                        session.restoring -> "正在恢复登录状态"
                        user == null -> "让积累，有自己的名字。"
                        else -> user.nickname.ifBlank { user.maskedIdentifier }
                    }
                    Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    if (!session.restoring) {
                        Text(
                            user?.let { "${it.provider.title} · ${it.maskedIdentifier}" }
                                ?: "登录或注册记金账户，继续记录你的黄金日常。",
                            color = GoldColors.Muted,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
            if (user == null && !session.restoring) {
                Button(onClick = onSignIn, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("登录 / 注册")
                }
            }
        }
    }
}

@Composable
private fun GoogleLinkDialog(actions: AccountActions, viewModel: AccountViewModel, onContinue: (String) -> Unit) {
    var password by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = viewModel::dismissGoogleLink,
        title = { Text("绑定 Google") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("验证当前账户的邮箱密码，然后选择要绑定的 Google 账号。")
                SecretField("当前账户密码", password, { password = it }, enabled = !actions.googleLinkBusy)
                actions.googleLinkError?.let { Notice(it, isError = true) }
            }
        },
        dismissButton = { TextButton(onClick = viewModel::dismissGoogleLink) { Text("取消") } },
        confirmButton = {
            Button(
                onClick = {
                    onContinue(password)
                    password = ""
                },
                enabled = !actions.googleLinkBusy && AuthValidation.validPassword(password),
            ) {
                Text(if (actions.googleLinkBusy) "验证中…" else "继续")
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AuthenticationSheet(form: AccountForm, viewModel: AccountViewModel, onGoogle: () -> Unit) {
    LaunchedEffect(form.remainingSeconds > 0) {
        if (form.remainingSeconds > 0) {
            while (true) {
                delay(1_000L)
                viewModel.tickCooldown()
            }
        }
    }
    ModalBottomSheet(onDismissRequest = viewModel::dismissForm, containerColor = GoldColors.Surface) {
        Column(
            Modifier.fillMaxWidth().heightIn(max = 680.dp).imePadding().verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val initialLogin = form.reauthentication == null && form.emailLinkIdentity == null
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when {
                        form.reauthentication != null -> "重新验证账号"
                        form.mode == FormMode.Register || form.mode == FormMode.Reset ||
                            form.mode == FormMode.LinkEmail -> form.mode.title
                        else -> "登录 / 注册"
                    },
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = viewModel::dismissForm) { Text("完成") }
            }
            if (initialLogin) {
                Text("欢迎来到记金", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text("登录后，账户持仓可在设备间同步。", color = GoldColors.Muted)
            }
            if (form.emailLinkIdentity != null) {
                Text("添加邮箱后，可在 iOS 上使用邮箱登录同一个记金账户。", color = GoldColors.Muted)
            }
            form.reauthentication?.let {
                Text("请验证 ${it.maskedIdentifier}。验证后会再次请你确认注销。", color = GoldColors.Muted)
            }
            if (form.showGoogle) {
                GoogleSignInButton(
                    if (initialLogin) "使用 Google 登录" else "重新验证 Google",
                    busy = form.working,
                    onClick = onGoogle,
                )
            }
            when {
                form.discovering -> Text("正在获取可用登录方式…", color = GoldColors.Muted)
                !form.showGoogle && !form.capabilities.phone && !form.capabilities.email -> {
                    Text("当前没有可用的 Android 登录方式。", color = GoldColors.Muted)
                    TextButton(onClick = viewModel::reloadCapabilities) { Text("重试") }
                }
                else -> {
                    if (initialLogin && form.capabilities.phone && form.capabilities.email) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (form.capabilities.phone) {
                                FilterChip(
                                    selected = form.mode == FormMode.Phone,
                                    onClick = { viewModel.changeMode(FormMode.Phone) },
                                    label = { Text("手机号") },
                                    enabled = !form.working,
                                )
                            }
                            if (form.capabilities.email) {
                                FilterChip(
                                    selected = form.mode != FormMode.Phone,
                                    onClick = { viewModel.changeMode(FormMode.Email) },
                                    label = { Text("邮箱") },
                                    enabled = !form.working,
                                )
                            }
                        }
                    }
                    if (form.modeEnabled) {
                        AuthFields(form, viewModel)
                    } else if (!form.showGoogle) {
                        Text("当前登录方式暂不可用。", color = GoldColors.Muted)
                        TextButton(onClick = viewModel::reloadCapabilities) { Text("重试") }
                    }
                }
            }
            form.notice?.let { Notice(it) }
            form.error?.let { Notice(it, isError = true) }
            if (initialLogin) Notice("游客记录独立保存在本机。登录后可在设置中主动导入。")
        }
    }
}

@Composable
private fun GoogleSignInButton(label: String, busy: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = !busy,
        modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp),
        shape = CircleShape,
        border = BorderStroke(1.dp, Color(0xFF8E918F)),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color(0xFF131314),
            contentColor = Color(0xFFE3E3E3),
        ),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            // Google supplies this unmodified mark on its Sign in with Google branding page.
            Image(
                painterResource(R.drawable.google_sign_in_logo), contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
            Text(if (busy) "处理中…" else label)
        }
    }
}

@Composable
private fun AuthFields(form: AccountForm, viewModel: AccountViewModel) {
    val phone = form.mode == FormMode.Phone
    val requiresCode = form.mode.codePurpose != null || form.mode == FormMode.LinkEmail
    val requiresConfirmation = form.mode == FormMode.Register || form.mode == FormMode.Reset ||
        form.mode == FormMode.LinkEmail
    OutlinedTextField(
        value = form.destinationInput,
        onValueChange = viewModel::inputDestination,
        label = { Text(if (phone) "中国大陆手机号" else "邮箱") },
        enabled = !form.working,
        keyboardOptions = KeyboardOptions(keyboardType = if (phone) KeyboardType.Phone else KeyboardType.Email),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    if (requiresCode) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            OutlinedTextField(
                value = form.code,
                onValueChange = viewModel::inputCode,
                label = { Text("验证码") },
                enabled = !form.working,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = viewModel::sendCode,
                enabled = form.normalizedDestination != null && form.remainingSeconds == 0 && !form.working,
            ) { Text(if (form.remainingSeconds > 0) "${form.remainingSeconds} 秒" else "获取验证码") }
        }
    }
    if (!phone) {
        SecretField("密码", form.password, viewModel::inputPassword, enabled = !form.working)
    }
    if (requiresConfirmation) {
        SecretField("确认密码", form.confirmation, viewModel::inputConfirmation, enabled = !form.working)
        Text("密码需包含 12–128 个字符。", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
    }
    if (phone && form.reauthentication == null) {
        Text("首次验证手机号会自动创建账号。", color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall)
    }
    Button(onClick = viewModel::submit, enabled = form.canSubmit, modifier = Modifier.fillMaxWidth()) {
        Text(
            when {
                form.working -> "处理中…"
                form.reauthentication != null -> "重新验证"
                form.mode == FormMode.Reset -> "重设密码"
                form.mode == FormMode.Register -> "注册"
                form.mode == FormMode.LinkEmail -> "绑定邮箱"
                else -> "登录"
            },
        )
    }
    if (form.mode == FormMode.Email && form.reauthentication == null) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TextButton(onClick = { viewModel.changeMode(FormMode.Register) }, enabled = !form.working) {
                Text("邮箱注册")
            }
            TextButton(onClick = { viewModel.changeMode(FormMode.Reset) }, enabled = !form.working) {
                Text("忘记密码")
            }
        }
    }
    if (form.mode == FormMode.Register || form.mode == FormMode.Reset) {
        TextButton(onClick = { viewModel.changeMode(FormMode.Email) }, enabled = !form.working) {
            Text("返回邮箱登录")
        }
    }
}

@Composable
private fun SecretField(label: String, value: String, onChange: (String) -> Unit, enabled: Boolean) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        enabled = enabled,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        visualTransformation = PasswordVisualTransformation(),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
internal fun Notice(text: String, isError: Boolean = false) {
    Text(
        text,
        color = if (isError) MaterialTheme.colorScheme.error else GoldColors.Muted,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
    )
}
