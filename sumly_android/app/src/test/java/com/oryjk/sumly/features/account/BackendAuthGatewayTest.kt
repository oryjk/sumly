package com.oryjk.sumly.features.account

import com.oryjk.sumly.core.network.ApiClient
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class BackendAuthGatewayTest {
    @Test
    fun resetPasswordUsesGoRouteAndNeverSendsPasswordUnderLoginKey() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(success())
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            gateway.resetPassword("tester@example.com", " twelve spaces ", "123456")

            val request = requireNotNull(server.takeRequest(5, TimeUnit.SECONDS))
            assertEquals("POST", request.method)
            assertEquals("/sumly/api/v1/app/auth/email/reset-password", request.path)
            assertNull(request.getHeader("Authorization"))
            val body = JSONObject(request.body.readUtf8())
            assertEquals(setOf("email", "new_password", "code"), body.keySet())
            assertEquals(" twelve spaces ", body.getString("new_password"))
        }
    }

    @Test
    fun deleteRequiresActiveBearerAndExactConfirmationBody() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(success())
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            gateway.deleteAccount("server-access-token")

            val request = requireNotNull(server.takeRequest(5, TimeUnit.SECONDS))
            assertEquals("DELETE", request.method)
            assertEquals("/sumly/api/v1/app/auth/account", request.path)
            assertEquals("Bearer server-access-token", request.getHeader("Authorization"))
            val body = JSONObject(request.body.readUtf8())
            assertEquals(setOf("confirmation"), body.keySet())
            assertEquals("DELETE", body.getString("confirmation"))
        }
    }

    @Test
    fun googleChallengeScopesLinkingOnlyToTheAuthenticatedAccount() = runBlocking {
        MockWebServer().use { server ->
            val challenge = """{"challenge_id":"issued-id","nonce":"issued-nonce","expires_in":300}"""
            server.enqueue(success(challenge))
            server.enqueue(success(challenge))
            server.enqueue(success())
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            val login = gateway.googleChallenge()
            val link = gateway.googleChallenge("email-session-token")
            gateway.linkGoogle(GoogleProof(link.id, "google-assertion"), "email-session-token")

            assertEquals("issued-nonce", login.nonce)
            val anonymous = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/google/challenge", anonymous.path)
            assertNull(anonymous.getHeader("Authorization"))
            val bound = server.nextRequest()
            assertEquals(anonymous.path, bound.path)
            assertEquals("Bearer email-session-token", bound.getHeader("Authorization"))
            val linkRequest = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/google/link", linkRequest.path)
            assertEquals("Bearer email-session-token", linkRequest.getHeader("Authorization"))
            val requestBody = JSONObject(linkRequest.body.readUtf8())
            assertEquals(setOf("challenge_id", "identity_token"), requestBody.keySet())
            assertEquals("issued-id", requestBody.getString("challenge_id"))
        }
    }

    @Test
    fun googleFirstCanAddAnEmailCredentialWithoutReplacingItsLogin() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(success("""{"retry_after":60,"expires_in":300}"""))
            server.enqueue(success())
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            assertEquals(60, gateway.sendEmailLinkCode("person@example.com", "google-session"))
            gateway.linkEmail("person@example.com", "verified password", "345678", "google-session")

            val code = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/email/link/code", code.path)
            assertEquals("Bearer google-session", code.getHeader("Authorization"))
            assertEquals(setOf("email"), JSONObject(code.body.readUtf8()).keySet())
            val link = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/email/link", link.path)
            assertEquals("Bearer google-session", link.getHeader("Authorization"))
            assertEquals(setOf("email", "password", "code"), JSONObject(link.body.readUtf8()).keySet())
        }
    }

    @Test
    fun olderCapabilitiesKeepEmailAvailableWithoutOfferingGoogle() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(success("""{"apple":true,"phone":false,"email":true}"""))
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))
            val capabilities = gateway.capabilities()
            assertEquals(true, capabilities.email)
            assertNull(capabilities.googleClientId)
        }
    }

    @Test
    fun googleLoginConflictDirectsTheUserToLinkTheirExistingEmailAccount() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(failure(409, "conflict"))
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            val error = runCatching { gateway.login(Login.Google(GoogleProof("challenge", "identity"))) }
                .exceptionOrNull()

            assertSame(AuthFailure.GoogleEmailAlreadyInUse, error)
            val login = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/google/login", login.path)
            assertNull(login.getHeader("Authorization"))
            assertEquals("identity", JSONObject(login.body.readUtf8()).getString("identity_token"))
        }
    }

    @Test
    fun invalidLinkProofIsDistinctFromAnExpiredBearer() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(failure(422, "invalid or expired verification proof"))
            server.enqueue(failure(422, "invalid or expired verification proof"))
            server.enqueue(failure(401, "invalid credentials"))
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))
            val proof = GoogleProof("challenge", "identity")

            assertSame(AuthFailure.InvalidEmailLinkProof, runCatching {
                gateway.linkEmail("person@example.com", "verified password", "345678", "google-bearer")
            }.exceptionOrNull())
            assertSame(AuthFailure.InvalidGoogleLinkProof, runCatching {
                gateway.linkGoogle(proof, "email-bearer")
            }.exceptionOrNull())
            assertSame(AuthFailure.Unauthorized, runCatching {
                gateway.linkGoogle(proof, "expired-bearer")
            }.exceptionOrNull())
        }
    }

    @Test
    fun googleReauthenticationUsesDedicatedBearerEndpointsAndReportsAnAccountMismatch() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(success("""{"challenge_id":"bound-id","nonce":"bound-nonce","expires_in":300}"""))
            server.enqueue(success("""{"token":"new-access","refresh_token":"new-refresh","expires_in":600,
                "user":{"id":42,"provider":"google","nickname":"","avatar_url":"","status":"active"}}"""))
            server.enqueue(failure(409, "Google identity does not belong to the authenticated account"))
            val gateway = BackendAuthGateway(ApiClient(server.url("/sumly/api/v1/").toString()))

            val challenge = gateway.googleReauthenticationChallenge("active-google-session")
            val proof = GoogleProof(challenge.id, "google-id-token")
            val renewed = gateway.reauthenticateGoogle(proof, "active-google-session")
            val mismatch = runCatching { gateway.reauthenticateGoogle(proof, "active-google-session") }
                .exceptionOrNull()

            val challengeRequest = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/google/reauthenticate/challenge", challengeRequest.path)
            assertEquals("Bearer active-google-session", challengeRequest.getHeader("Authorization"))
            assertEquals(0, JSONObject(challengeRequest.body.readUtf8()).length())
            val reauthRequest = server.nextRequest()
            assertEquals("/sumly/api/v1/app/auth/google/reauthenticate", reauthRequest.path)
            assertEquals("Bearer active-google-session", reauthRequest.getHeader("Authorization"))
            assertEquals("bound-id", JSONObject(reauthRequest.body.readUtf8()).getString("challenge_id"))
            assertEquals("bound-nonce", challenge.nonce)
            assertEquals("new-refresh", renewed.refreshToken)
            assertSame(AuthFailure.AccountMismatch, mismatch)
        }
    }

    private fun MockWebServer.nextRequest() = requireNotNull(takeRequest(5, TimeUnit.SECONDS))

    private fun success(data: String = "{}") = MockResponse()
        .setHeader("Content-Type", "application/json")
        .setBody("""{"code":0,"message":"success","data":$data}""")

    private fun failure(status: Int, message: String) = MockResponse()
        .setResponseCode(status)
        .setHeader("Content-Type", "application/json")
        .setBody("""{"code":$status,"message":"$message","data":null}""")
}
