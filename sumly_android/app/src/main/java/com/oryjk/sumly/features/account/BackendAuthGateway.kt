package com.oryjk.sumly.features.account

import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.core.network.ApiException
import java.io.IOException
import org.json.JSONException
import org.json.JSONObject

internal class BackendAuthGateway(private val api: ApiClient) : AuthGateway {
    override suspend fun capabilities(): AuthCapabilities = request {
        val data = api.get("app/auth/capabilities")
        AuthCapabilities(
            phone = data.getBoolean("phone"),
            email = data.getBoolean("email"),
            apple = data.getBoolean("apple"),
            googleClientId = data.optString("google_client_id").takeIf {
                data.optBoolean("google") && it.endsWith(".apps.googleusercontent.com")
            },
        )
    }

    override suspend fun sendCode(destination: String, purpose: CodePurpose): Int = request {
        val data = when (purpose) {
            CodePurpose.PhoneLogin -> api.post("app/auth/phone/code", fields("phone_number" to destination))
            CodePurpose.Register, CodePurpose.ResetPassword -> api.post(
                "app/auth/email/code", fields("email" to destination, "purpose" to purpose.serverValue),
            )
        }
        data.getInt("retry_after").coerceAtLeast(0)
    }

    override suspend fun login(login: Login): LoginResult = request(
        failedLogin = true,
        conflict = AuthFailure.GoogleEmailAlreadyInUse.takeIf { login is Login.Google },
    ) {
        val data = when (login) {
            is Login.Phone -> api.post(
                "app/auth/phone/login", fields("phone_number" to login.number, "code" to login.code),
            )
            is Login.Email -> api.post(
                "app/auth/email/login", fields("email" to login.email, "password" to login.password),
            )
            is Login.Register -> api.post(
                "app/auth/email/register",
                fields("email" to login.email, "password" to login.password, "code" to login.code),
            )
            is Login.Google -> api.post("app/auth/google/login", googleFields(login.proof))
        }
        AuthJson.decodeLogin(data)
    }

    override suspend fun googleChallenge(accessToken: String?): GoogleChallenge =
        request(forbidden = AuthFailure.LinkReauthentication.takeIf { accessToken != null }) {
            decodeGoogleChallenge(api.post("app/auth/google/challenge", JSONObject(), accessToken = accessToken))
        }

    override suspend fun googleReauthenticationChallenge(accessToken: String): GoogleChallenge =
        request(forbidden = AuthFailure.AccountMismatch) {
            decodeGoogleChallenge(
                api.post("app/auth/google/reauthenticate/challenge", JSONObject(), accessToken = accessToken),
            )
        }

    override suspend fun reauthenticateGoogle(proof: GoogleProof, accessToken: String): LoginResult =
        request(
            forbidden = AuthFailure.AccountMismatch,
            conflict = AuthFailure.AccountMismatch,
            invalidProof = AuthFailure.InvalidGoogleLinkProof,
        ) {
            AuthJson.decodeLogin(
                api.post("app/auth/google/reauthenticate", googleFields(proof), accessToken = accessToken),
            )
        }

    override suspend fun linkGoogle(proof: GoogleProof, accessToken: String) {
        request(
            forbidden = AuthFailure.LinkReauthentication,
            conflict = AuthFailure.GoogleLinkConflict,
            invalidProof = AuthFailure.InvalidGoogleLinkProof,
        ) {
            api.post("app/auth/google/link", googleFields(proof), accessToken = accessToken)
        }
    }

    override suspend fun sendEmailLinkCode(email: String, accessToken: String): Int =
        request(forbidden = AuthFailure.LinkReauthentication, conflict = AuthFailure.EmailLinkConflict) {
            api.post("app/auth/email/link/code", fields("email" to email), accessToken = accessToken)
                .getInt("retry_after").coerceAtLeast(0)
        }

    override suspend fun linkEmail(email: String, password: String, code: String, accessToken: String) {
        request(
            forbidden = AuthFailure.LinkReauthentication,
            conflict = AuthFailure.EmailLinkConflict,
            invalidProof = AuthFailure.InvalidEmailLinkProof,
        ) {
            api.post(
                "app/auth/email/link",
                fields("email" to email, "password" to password, "code" to code),
                accessToken = accessToken,
            )
        }
    }

    override suspend fun resetPassword(email: String, password: String, code: String) {
        request {
            api.post(
                "app/auth/email/reset-password",
                fields("email" to email, "new_password" to password, "code" to code),
            )
        }
    }

    override suspend fun me(token: String): AccountUser = request {
        AuthJson.decodeUser(api.get("app/auth/me", accessToken = token))
    }

    override suspend fun refresh(refreshToken: String): LoginResult = request {
        AuthJson.decodeLogin(api.post("app/auth/refresh", fields("refresh_token" to refreshToken)))
    }

    override suspend fun logout(refreshToken: String) {
        request { api.post("app/auth/logout", fields("refresh_token" to refreshToken)) }
    }

    override suspend fun deleteAccount(token: String) {
        request(reauthOnDenial = true) {
            api.delete("app/auth/account", accessToken = token, body = fields("confirmation" to "DELETE"))
        }
    }

    private fun fields(vararg values: Pair<String, String>) = JSONObject().apply {
        values.forEach { (key, value) -> put(key, value) }
    }

    private fun googleFields(proof: GoogleProof) =
        fields("challenge_id" to proof.challengeId, "identity_token" to proof.identityToken)

    private fun decodeGoogleChallenge(data: JSONObject): GoogleChallenge {
        val id = data.getString("challenge_id")
        val nonce = data.getString("nonce")
        val expires = data.getInt("expires_in")
        if (id.isBlank() || nonce.isBlank() || expires !in 1..600) throw AuthFailure.Malformed
        return GoogleChallenge(id, nonce, expires)
    }

    private suspend fun <T> request(
        reauthOnDenial: Boolean = false,
        failedLogin: Boolean = false,
        forbidden: AuthFailure? = null,
        conflict: AuthFailure? = null,
        invalidProof: AuthFailure? = null,
        call: suspend () -> T,
    ): T {
        return try {
            call()
        } catch (error: ApiException) {
            throw when {
                reauthOnDenial && (error.httpStatus == 401 || error.httpStatus == 403) -> AuthFailure.Reauthenticate
                forbidden != null && error.httpStatus == 403 -> forbidden
                conflict != null && error.httpStatus == 409 -> conflict
                invalidProof != null && error.httpStatus == 422 &&
                    error.message == "invalid or expired verification proof" -> invalidProof
                failedLogin && error.httpStatus == 401 -> AuthFailure.Server("登录信息有误，请核对后重试。")
                error.httpStatus == 401 -> AuthFailure.Unauthorized
                error.httpStatus == 404 || error.httpStatus == 503 -> AuthFailure.Unavailable
                error.httpStatus == 429 -> AuthFailure.Server("操作过于频繁，请稍后重试。")
                error.code == -1 && (error.httpStatus == 0 || error.httpStatus in 200..299) -> AuthFailure.Malformed
                else -> AuthFailure.Server(error.message.orEmpty().take(240))
            }
        } catch (_: JSONException) {
            throw AuthFailure.Malformed
        } catch (_: IOException) {
            throw AuthFailure.Network
        }
    }
}

internal object AuthJson {
    fun decodeUser(data: JSONObject): AccountUser {
        val id = data.getLong("id")
        val provider = AccountProvider.entries.firstOrNull { it.serverValue == data.get("provider") }
        if (id <= 0 || provider == null) throw AuthFailure.Malformed
        return AccountUser(
            id = id,
            nickname = data.string("nickname"),
            avatarUrl = data.string("avatar_url"),
            status = data.string("status"),
            provider = provider,
            email = data.nullableString("email"),
            phoneNumber = data.nullableString("phone_number"),
        )
    }

    fun decodeLogin(data: JSONObject) = LoginResult(
        token = data.string("token"),
        refreshToken = data.string("refresh_token"),
        expiresInSeconds = data.getInt("expires_in"),
        user = decodeUser(data.getJSONObject("user")),
    ).also(LoginResult::validate)

    fun encodeLogin(result: LoginResult): JSONObject = JSONObject()
        .put("token", result.token)
        .put("refresh_token", result.refreshToken)
        .put("expires_in", result.expiresInSeconds)
        .put("user", JSONObject()
            .put("id", result.user.id)
            .put("nickname", result.user.nickname)
            .put("avatar_url", result.user.avatarUrl)
            .put("status", result.user.status)
            .put("provider", result.user.provider.serverValue)
            .put("email", result.user.email ?: JSONObject.NULL)
            .put("phone_number", result.user.phoneNumber ?: JSONObject.NULL))

    private fun JSONObject.string(key: String): String =
        get(key) as? String ?: throw AuthFailure.Malformed

    private fun JSONObject.nullableString(key: String): String? =
        if (isNull(key)) null else string(key)
}
