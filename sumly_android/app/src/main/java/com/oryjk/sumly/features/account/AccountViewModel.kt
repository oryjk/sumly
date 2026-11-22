package com.oryjk.sumly.features.account

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

internal enum class FormMode(val title: String) {
    Phone("手机号登录"),
    Email("邮箱登录"),
    Register("注册邮箱账户"),
    Reset("重设密码"),
    LinkEmail("添加邮箱登录");

    val codePurpose: CodePurpose?
        get() = when (this) {
            Phone -> CodePurpose.PhoneLogin
            Email, LinkEmail -> null
            Register -> CodePurpose.Register
            Reset -> CodePurpose.ResetPassword
        }
}

internal data class AccountForm(
    val mode: FormMode = FormMode.Email,
    val destinationInput: String = "",
    val password: String = "",
    val confirmation: String = "",
    val code: String = "",
    val capabilities: AuthCapabilities = AuthCapabilities.Disabled,
    val discovering: Boolean = true,
    val working: Boolean = false,
    val remainingSeconds: Int = 0,
    val error: String? = null,
    val notice: String? = null,
    val reauthentication: DeleteAccountIntent? = null,
    val emailLinkIdentity: AccountIdentity? = null,
    val emailLinkNeedsProof: Boolean = false,
) {
    val normalizedDestination: String?
        get() = if (mode == FormMode.Phone) {
            AuthValidation.phone(destinationInput)
        } else {
            AuthValidation.email(destinationInput).takeIf(AuthValidation::validEmail)
        }
    val modeEnabled: Boolean
        get() = when (mode) {
            FormMode.Phone -> capabilities.phone &&
                (reauthentication == null || reauthentication.identity.provider == AccountProvider.Phone)
            FormMode.Email -> capabilities.email &&
                (reauthentication == null || reauthentication.identity.provider == AccountProvider.Email)
            FormMode.Register, FormMode.Reset -> capabilities.email && reauthentication == null
            FormMode.LinkEmail -> capabilities.email && emailLinkIdentity != null && !emailLinkNeedsProof
        }
    val canSubmit: Boolean
        get() = modeEnabled && !working && normalizedDestination != null && when (mode) {
            FormMode.Phone -> AuthValidation.validCode(code)
            FormMode.Email -> AuthValidation.validPassword(password)
            FormMode.Register, FormMode.Reset, FormMode.LinkEmail -> AuthValidation.validPassword(password) &&
                password == confirmation && AuthValidation.validCode(code)
        }
    val showGoogle: Boolean
        get() = capabilities.googleClientId != null && when {
            emailLinkIdentity != null -> emailLinkNeedsProof
            reauthentication != null -> reauthentication.identity.provider == AccountProvider.Google
            else -> true
        }

    override fun toString() = "AccountForm(mode=$mode)"
}

internal data class AccountActions(
    val busy: Boolean = false,
    val confirmLogout: AccountIdentity? = null,
    val confirmDelete: DeleteAccountIntent? = null,
    val googleLink: AccountIdentity? = null,
    val googleLinkBusy: Boolean = false,
    val googleLinkError: String? = null,
    val error: String? = null,
    val notice: String? = null,
)

internal typealias GoogleCredentialPicker = suspend (clientId: String, nonce: String) -> String?

class AccountViewModel internal constructor(
    private val gateway: AuthGateway,
    store: CredentialStore,
    isUnauthorized: (Exception) -> Boolean,
    onAccountDeleted: suspend (Long) -> Unit = {},
    private val clearGoogleCredentialState: suspend () -> Unit = {},
) : ViewModel() {
    val session = AuthSession(
        gateway, store, viewModelScope, isUnauthorized = isUnauthorized, onAccountDeleted = onAccountDeleted,
    )

    private val formModel = MutableStateFlow<AccountForm?>(null)
    internal val form = formModel.asStateFlow()
    private val actionModel = MutableStateFlow(AccountActions())
    internal val actions = actionModel.asStateFlow()
    private val settingsCapabilityModel = MutableStateFlow(AuthCapabilities.Disabled)
    internal val settingsCapabilities = settingsCapabilityModel.asStateFlow()

    private val cooldowns = mutableMapOf<String, Long>()
    private var formVersion = 0L
    private var discoveryJob: Job? = null
    private var requestJob: Job? = null
    private var googleLinkJob: Job? = null
    private var googleLinkVersion = 0L

    init {
        viewModelScope.launch { session.restore() }
    }

    internal fun openSignIn() {
        if (session.state.value.restoring || session.state.value.user != null) return
        openForm()
    }

    private fun openForm(intent: DeleteAccountIntent? = null) {
        formVersion++
        formModel.value = AccountForm(
            mode = if (intent?.identity?.provider == AccountProvider.Phone) FormMode.Phone else FormMode.Email,
            reauthentication = intent,
        )
        reloadCapabilities()
    }

    internal fun dismissForm() {
        val current = formModel.value ?: return
        formVersion++
        formModel.value = null
        discoveryJob?.cancel()
        requestJob?.cancel()
        viewModelScope.launch {
            if (current.reauthentication != null) session.cancelAccountDeletion()
            else if (current.emailLinkIdentity == null) session.cancelPendingLogin()
        }
    }

    internal fun reloadCapabilities() {
        if (formModel.value == null || discoveryJob?.isActive == true) return
        val version = formVersion
        formModel.update { it?.copy(discovering = true, capabilities = AuthCapabilities.Disabled, error = null) }
        discoveryJob = viewModelScope.launch {
            try {
                val capabilities = gateway.capabilities()
                updateForm(version) {
                    val mode = if (it.mode == FormMode.Email && it.reauthentication == null &&
                        !capabilities.email && capabilities.phone
                    ) FormMode.Phone else it.mode
                    it.copy(mode = mode, capabilities = capabilities, discovering = false)
                }
            } catch (error: AuthFailure) {
                updateForm(version) { it.copy(discovering = false, error = error.message) }
            }
        }
    }

    internal fun changeMode(mode: FormMode) {
        val previous = formModel.value ?: return
        if (previous.working || previous.reauthentication != null || previous.emailLinkIdentity != null) return
        val destination = previous.destinationInput.takeIf { (previous.mode == FormMode.Phone) == (mode == FormMode.Phone) }
        formModel.value = previous.copy(
            mode = mode, destinationInput = destination.orEmpty(), password = "", confirmation = "",
            code = "", error = null, notice = null,
        )
        tickCooldown()
    }

    internal fun inputDestination(value: String) {
        editForm { it.copy(destinationInput = value) }
        tickCooldown()
    }

    internal fun inputPassword(value: String) = editForm { it.copy(password = value) }
    internal fun inputConfirmation(value: String) = editForm { it.copy(confirmation = value) }
    internal fun inputCode(value: String) = editForm {
        it.copy(code = value.filter { digit -> digit in '0'..'9' }.take(6))
    }

    internal fun tickCooldown() {
        val now = SystemClock.elapsedRealtime()
        cooldowns.entries.removeAll { (_, until) -> until <= now }
        formModel.update { current ->
            current?.copy(remainingSeconds = remainingSeconds(cooldownKey(current)))
        }
    }

    internal fun sendCode() {
        val current = formModel.value ?: return
        val purpose = current.mode.codePurpose
        val linkIdentity = current.emailLinkIdentity
        if (purpose == null && linkIdentity == null) return
        val destination = current.normalizedDestination ?: return
        val key = cooldownKey(current) ?: return
        if (!current.modeEnabled || current.working || remainingSeconds(key) > 0) return
        val version = formVersion
        formModel.value = current.copy(working = true, error = null, notice = null)
        requestJob = viewModelScope.launch {
            try {
                val waitSeconds = if (linkIdentity != null) {
                    session.authorized(linkIdentity) { gateway.sendEmailLinkCode(destination, it) }
                } else {
                    gateway.sendCode(destination, requireNotNull(purpose))
                }
                cooldowns[key] = SystemClock.elapsedRealtime() + waitSeconds.toLong() * 1_000
                updateForm(version) {
                    it.copy(
                        working = false,
                        remainingSeconds = remainingSeconds(key),
                        notice = if (purpose == CodePurpose.PhoneLogin) {
                            "验证码已发送，5 分钟内有效。"
                        } else {
                            "如果此邮箱符合条件，将收到验证码。"
                        },
                    )
                }
            } catch (error: AuthFailure) {
                showFormFailure(version, error)
            }
        }
    }

    internal fun submit() {
        val current = formModel.value ?: return
        val destination = current.normalizedDestination ?: return
        if (!current.canSubmit) return
        val version = formVersion
        val originalSession = session.state.value
        val originalIdentity = originalSession.identity
        val guestOrigin = originalSession.takeIf { current.reauthentication == null }
        formModel.value = current.copy(working = true, error = null, notice = null)
        requestJob = viewModelScope.launch {
            try {
                if (current.mode == FormMode.LinkEmail) {
                    val identity = requireNotNull(current.emailLinkIdentity)
                    session.authorized(identity) {
                        gateway.linkEmail(destination, current.password, current.code, it)
                    }
                    if (formVersion == version) {
                        formModel.value = null
                        actionModel.update {
                            it.copy(notice = "邮箱登录已添加。可以在 iOS 上用此邮箱登录同一个记金账户。")
                        }
                    }
                    try {
                        session.reloadUser(identity)
                    } catch (_: AuthFailure) {
                        // The credential was bound; the profile will be reloaded with a future session.
                    }
                    return@launch
                }
                if (current.mode == FormMode.Reset) {
                    gateway.resetPassword(destination, current.password, current.code)
                    session.clearPasswordResetSession(destination, originalIdentity)
                    updateForm(version) {
                        it.copy(
                            mode = FormMode.Email, password = "", confirmation = "", code = "", working = false,
                            notice = "密码已重设，请使用新密码登录。",
                        )
                    }
                    return@launch
                }
                val command = when (current.mode) {
                    FormMode.Phone -> Login.Phone(destination, current.code)
                    FormMode.Email -> Login.Email(destination, current.password)
                    FormMode.Register -> Login.Register(destination, current.password, current.code)
                    FormMode.Reset, FormMode.LinkEmail -> error("Handled above")
                }
                val nextIntent = session.login(command, current.reauthentication, guestOrigin)
                finishLogin(version, nextIntent)
            } catch (error: AuthFailure) {
                showFormFailure(version, error)
            }
        }
    }

    internal suspend fun signInWithGoogle(pickCredential: GoogleCredentialPicker) {
        val current = formModel.value ?: return
        if (current.working || !current.showGoogle) return
        val clientId = current.capabilities.googleClientId ?: return
        val version = formVersion
        val origin = session.state.value
        val linkIdentity = current.emailLinkIdentity
        val reauthenticating = linkIdentity ?: current.reauthentication?.identity
        requestJob = currentCoroutineContext()[Job]
        formModel.value = current.copy(working = true, error = null, notice = null)
        try {
            val challenge = if (reauthenticating != null) {
                session.authorized(reauthenticating, gateway::googleReauthenticationChallenge)
            } else {
                gateway.googleChallenge()
            }
            val proof = googleProof(clientId, challenge, pickCredential) ?: return
            if (formVersion != version) return
            if (linkIdentity != null) {
                val verified = session.reauthenticate(linkIdentity, Login.Google(proof))
                updateForm(version) {
                    it.copy(
                        code = "", emailLinkIdentity = verified, emailLinkNeedsProof = false,
                        notice = "Google 验证完成，请获取绑定邮箱的验证码。",
                    )
                }
            } else {
                val guestOrigin = origin.takeIf { current.reauthentication == null }
                val nextIntent = session.login(Login.Google(proof), current.reauthentication, guestOrigin)
                finishLogin(version, nextIntent)
            }
        } catch (error: AuthFailure) {
            showFormFailure(version, error)
        } finally {
            updateForm(version) { it.copy(working = false) }
        }
    }

    internal suspend fun loadSettingsCapabilities(identity: AccountIdentity?) {
        settingsCapabilityModel.value = AuthCapabilities.Disabled
        if (identity == null) return
        val capabilities = try {
            gateway.capabilities()
        } catch (_: AuthFailure) {
            return
        }
        currentCoroutineContext().ensureActive()
        if (session.state.value.identity == identity) settingsCapabilityModel.value = capabilities
    }

    internal fun openEmailLink() {
        val identity = session.state.value.identity ?: return
        val capabilities = settingsCapabilityModel.value
        if (identity.provider != AccountProvider.Google || !capabilities.email ||
            capabilities.googleClientId == null || session.state.value.user?.email != null
        ) return
        actionModel.update { it.copy(error = null, notice = null) }
        formVersion++
        formModel.value = AccountForm(
            mode = FormMode.LinkEmail, discovering = false, capabilities = capabilities, emailLinkIdentity = identity,
        )
    }

    internal fun openGoogleLink() {
        val identity = session.state.value.identity ?: return
        val validEmail = session.state.value.user?.email?.let(AuthValidation::validEmail) == true
        if (identity.provider != AccountProvider.Email || !validEmail ||
            settingsCapabilityModel.value.googleClientId == null
        ) return
        googleLinkVersion++
        actionModel.update { it.copy(googleLink = identity, googleLinkError = null, error = null, notice = null) }
    }

    internal fun dismissGoogleLink() {
        googleLinkVersion++
        googleLinkJob?.cancel()
        actionModel.update { it.copy(googleLink = null, googleLinkBusy = false, googleLinkError = null) }
    }

    internal suspend fun linkGoogle(password: String, pickCredential: GoogleCredentialPicker) {
        val actions = actionModel.value
        val identity = actions.googleLink ?: return
        val email = session.state.value.user?.email ?: return
        val clientId = settingsCapabilityModel.value.googleClientId ?: return
        if (actions.googleLinkBusy || !AuthValidation.validPassword(password)) return
        val version = googleLinkVersion
        googleLinkJob = currentCoroutineContext()[Job]
        actionModel.update { it.copy(googleLinkBusy = true, googleLinkError = null) }
        try {
            val verified = session.reauthenticate(identity, Login.Email(AuthValidation.email(email), password))
            if (googleLinkVersion != version) return
            actionModel.update { it.copy(googleLink = verified) }
            val challenge = session.authorized(verified) { gateway.googleChallenge(it) }
            val proof = googleProof(clientId, challenge, pickCredential) ?: return
            if (googleLinkVersion != version) return
            session.authorized(verified) { gateway.linkGoogle(proof, it) }
            if (googleLinkVersion == version) {
                actionModel.update {
                    it.copy(
                        googleLink = null, notice = "Google 已绑定。下次可用 Google 登录同一个记金账户。",
                    )
                }
            }
        } catch (error: AuthFailure) {
            if (googleLinkVersion == version) actionModel.update { it.copy(googleLinkError = error.message) }
        } finally {
            if (googleLinkVersion == version) actionModel.update { it.copy(googleLinkBusy = false) }
        }
    }

    private suspend fun googleProof(
        clientId: String,
        challenge: GoogleChallenge,
        pickCredential: GoogleCredentialPicker,
    ): GoogleProof? {
        val deadline = SystemClock.elapsedRealtime() + challenge.expiresInSeconds * 1_000L
        val token = pickCredential(clientId, challenge.nonce) ?: return null
        currentCoroutineContext().ensureActive()
        if (SystemClock.elapsedRealtime() >= deadline) throw AuthFailure.GoogleProofExpired
        if (token.isBlank()) throw AuthFailure.GoogleCredentialUnavailable
        return GoogleProof(challenge.id, token)
    }

    private fun showFormFailure(version: Long, error: AuthFailure) {
        updateForm(version) {
            it.copy(
                working = false, error = error.message,
                emailLinkNeedsProof = it.emailLinkNeedsProof || error == AuthFailure.LinkReauthentication,
            )
        }
    }

    private fun finishLogin(version: Long, nextIntent: DeleteAccountIntent?) {
        if (formVersion != version) return
        formModel.value = null
        actionModel.value = AccountActions(confirmDelete = nextIntent)
    }

    internal fun showLogoutConfirmation() {
        actionModel.update { it.copy(confirmLogout = session.state.value.identity, error = null) }
    }

    internal fun dismissLogoutConfirmation() {
        actionModel.update { it.copy(confirmLogout = null) }
    }

    internal fun logout() {
        val confirming = actionModel.value.confirmLogout ?: return
        if (actionModel.value.busy || confirming != session.state.value.identity) return
        actionModel.update { it.copy(busy = true, confirmLogout = null, notice = null) }
        viewModelScope.launch {
            try {
                session.logout(confirming)
                clearGoogleCredentialState()
            } catch (error: AuthFailure) {
                actionModel.update { it.copy(error = error.message) }
            } finally {
                actionModel.update { it.copy(busy = false) }
            }
        }
    }

    internal fun showDeleteConfirmation() {
        if (actionModel.value.busy) return
        viewModelScope.launch {
            val intent = session.beginAccountDeletion()
            actionModel.update { it.copy(confirmDelete = intent, error = null, notice = null) }
        }
    }

    internal fun dismissDeleteConfirmation() {
        actionModel.update { it.copy(confirmDelete = null) }
        viewModelScope.launch { session.cancelAccountDeletion() }
    }

    internal fun confirmAccountDeletion() {
        val intent = actionModel.value.confirmDelete ?: return
        if (actionModel.value.busy) return
        actionModel.update { it.copy(busy = true, confirmDelete = null) }
        viewModelScope.launch {
            try {
                session.deleteAccount(intent)
            } catch (error: AuthFailure) {
                if (error == AuthFailure.Reauthenticate && intent.identity.provider != AccountProvider.Apple) {
                    openForm(intent)
                } else {
                    actionModel.update { it.copy(error = error.message) }
                }
            } finally {
                actionModel.update { it.copy(busy = false) }
            }
        }
    }

    private fun cooldownKey(form: AccountForm): String? = form.normalizedDestination?.let { address ->
        when (form.mode) {
            FormMode.Phone -> "phone:$address"
            FormMode.LinkEmail -> "email-link:${form.emailLinkIdentity?.userId}:$address"
            else -> "email:$address"
        }
    }

    private fun remainingSeconds(key: String?): Int {
        val deadline = cooldowns[key] ?: return 0
        return ((deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0) + 999).div(1_000).toInt()
    }

    private fun editForm(change: (AccountForm) -> AccountForm) {
        formModel.update { form -> form?.let { if (it.working) it else change(it).copy(error = null) } }
    }

    private fun updateForm(version: Long, change: (AccountForm) -> AccountForm) {
        if (formVersion == version) formModel.update { it?.let(change) }
    }
}
