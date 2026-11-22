package com.oryjk.sumly.features.account

import java.util.Locale
import java.util.UUID

enum class AccountProvider(val serverValue: String, val title: String) {
    Apple("apple", "Apple"),
    Phone("phone", "手机号"),
    Email("email", "邮箱"),
    Google("google", "Google"),
}

data class AccountUser(
    val id: Long,
    val nickname: String,
    val avatarUrl: String,
    val status: String,
    val provider: AccountProvider,
    val email: String?,
    val phoneNumber: String?,
) {
    val maskedIdentifier: String
        get() = when {
            phoneNumber != null -> "${phoneNumber.take(6)}****${phoneNumber.takeLast(4)}"
            email != null -> "${email.take(1)}***@${email.substringAfter('@')}"
            provider == AccountProvider.Apple -> "Apple 私密账户"
            else -> "${provider.title}账户"
        }

    override fun toString() = "AccountUser(provider=$provider)"
}

data class AccountIdentity(val userId: Long, val provider: AccountProvider, val generation: Long)

data class AccountSessionState(
    val user: AccountUser? = null,
    val generation: Long = 0,
    val restoring: Boolean = true,
    val notice: String? = null,
) {
    val identity: AccountIdentity?
        get() = user?.let { AccountIdentity(it.id, it.provider, generation) }
}

internal enum class CodePurpose(val serverValue: String) {
    PhoneLogin(""), Register("register"), ResetPassword("reset_password"),
}

internal sealed interface Login {
    data class Phone(val number: String, val code: String) : Login {
        override fun toString() = "Phone"
    }
    data class Email(val email: String, val password: String) : Login {
        override fun toString() = "Email"
    }
    data class Register(val email: String, val password: String, val code: String) : Login {
        override fun toString() = "Register"
    }
    data class Google(val proof: GoogleProof) : Login {
        override fun toString() = "Google"
    }
}

internal class GoogleProof(val challengeId: String, val identityToken: String)

internal class GoogleChallenge(val id: String, val nonce: String, val expiresInSeconds: Int)

internal data class AuthCapabilities(
    val phone: Boolean,
    val email: Boolean,
    val apple: Boolean,
    val googleClientId: String? = null,
) {
    companion object {
        val Disabled = AuthCapabilities(phone = false, email = false, apple = false)
    }
}

internal class LoginResult(
    val token: String,
    val refreshToken: String,
    val expiresInSeconds: Int,
    val user: AccountUser,
) {
    fun validate() {
        if (token.isBlank() || refreshToken.isBlank() || expiresInSeconds !in 1..86_400) {
            throw AuthFailure.Malformed
        }
    }
}

internal data class StoredSession(
    val credentials: LoginResult,
    val expiresAtMillis: Long,
    val primaryLoginAtMillis: Long,
)

internal data class DeleteAccountIntent(
    val identity: AccountIdentity,
    val maskedIdentifier: String,
    val id: UUID = UUID.randomUUID(),
)

internal interface AuthGateway {
    suspend fun capabilities(): AuthCapabilities
    suspend fun sendCode(destination: String, purpose: CodePurpose): Int
    suspend fun login(login: Login): LoginResult
    suspend fun resetPassword(email: String, password: String, code: String)
    suspend fun me(token: String): AccountUser
    suspend fun refresh(refreshToken: String): LoginResult
    suspend fun logout(refreshToken: String)
    suspend fun deleteAccount(token: String)
    suspend fun googleChallenge(accessToken: String? = null): GoogleChallenge = throw AuthFailure.Unavailable
    suspend fun googleReauthenticationChallenge(accessToken: String): GoogleChallenge = throw AuthFailure.Unavailable
    suspend fun reauthenticateGoogle(proof: GoogleProof, accessToken: String): LoginResult = throw AuthFailure.Unavailable
    suspend fun linkGoogle(proof: GoogleProof, accessToken: String) { throw AuthFailure.Unavailable }
    suspend fun sendEmailLinkCode(email: String, accessToken: String): Int = throw AuthFailure.Unavailable
    suspend fun linkEmail(email: String, password: String, code: String, accessToken: String) {
        throw AuthFailure.Unavailable
    }
}

internal interface CredentialStore {
    fun load(): StoredSession?
    fun save(value: StoredSession)
    fun clear()
}

internal sealed class AuthFailure(message: String) : Exception(message) {
    data object Unauthorized : AuthFailure("登录已失效，请重新登录。")
    data object Unavailable : AuthFailure("登录服务暂不可用，请稍后重试。")
    data object Network : AuthFailure("网络连接失败，请稍后重试。")
    data object Malformed : AuthFailure("服务返回异常，请稍后重试。")
    data object Stale : AuthFailure("操作已取消，请重试。")
    data object AccountMismatch : AuthFailure("请使用当前账户的原登录方式和账号重新验证。")
    data object Reauthenticate : AuthFailure("请重新验证原账号，并在 5 分钟内再次确认注销。")
    data object LinkReauthentication : AuthFailure("请重新验证当前账号，再继续绑定。")
    data object GoogleCredentialUnavailable :
        AuthFailure("无法取得 Google 登录凭证。请检查 Google Play 服务，或使用邮箱登录。")
    data object GoogleProofExpired : AuthFailure("Google 验证已过期，请重试。")
    data object InvalidGoogleLinkProof : AuthFailure("Google 验证无效或已过期，请重新选择 Google 账号。")
    data object InvalidEmailLinkProof : AuthFailure("验证码无效或已过期，请核对验证码，或重新获取。")
    data object GoogleEmailAlreadyInUse : AuthFailure("请先通过邮箱登录原账户，再绑定 Google。")
    data object GoogleLinkConflict : AuthFailure("此 Google 账号无法绑定，可能已与其他记金账户关联。")
    data object EmailLinkConflict : AuthFailure("此邮箱已配置登录方式或已由其他记金账户使用。")
    data object SafeStorage : AuthFailure("无法访问安全凭据，请解锁设备后重试。")
    data object SignOutStorage : AuthFailure("清除本机安全凭据失败，请解锁设备并重新打开应用核对登录状态。")
    class Server(message: String) : AuthFailure(message.ifBlank { "操作失败，请稍后重试。" })
}

internal object AuthValidation {
    private val emailPattern = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
    private val phonePattern = Regex("^1[3-9][0-9]{9}$")
    private val codePattern = Regex("^[0-9]{6}$")

    fun validPassword(value: String): Boolean =
        value.codePointCount(0, value.length) in 12..128 && value.toByteArray(Charsets.UTF_8).size <= 512

    fun email(value: String): String = value.trim().lowercase(Locale.ROOT)

    fun validEmail(value: String): Boolean {
        val normalized = email(value)
        return normalized.toByteArray(Charsets.UTF_8).size <= 254 && emailPattern.matches(normalized)
    }

    fun phone(value: String): String? =
        value.trim().removePrefix("+86").takeIf(phonePattern::matches)?.let { "+86$it" }

    fun validCode(value: String): Boolean = codePattern.matches(value)
}
