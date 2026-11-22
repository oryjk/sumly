package com.oryjk.sumly.core.network

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ApiClientTest {
    @Test
    fun quoteKeepsProxyPrefixAndDecodesSuccessEnvelope() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"code":0,"message":"ok","data":{"cny_per_gram":920.5}}"""))
            val api = ApiClient(server.url("/sumly/api/v1/").toString())

            val quote = api.get("app/market/gold/quote", mapOf("basis" to "上海 黄金"))

            assertEquals(920.5, quote.getDouble("cny_per_gram"), 0.0)
            val request = server.takeRequest()
            assertEquals("/sumly/api/v1/app/market/gold/quote", request.requestUrl?.encodedPath)
            assertEquals("上海 黄金", request.requestUrl?.queryParameter("basis"))
        }
    }

    @Test
    fun deletionSendsConfirmationAndKeepsServerFailureCode() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(403).setBody("""{"code":40319,"message":"请重新验证","data":null}"""))
            val api = ApiClient(server.url("/sumly/api/v1/").toString())

            val failure = assertThrows(ApiException::class.java) {
                runBlocking {
                    api.delete("app/auth/account", "session-token", JSONObject().put("confirmation", "DELETE"))
                }
            }

            assertEquals(403, failure.httpStatus)
            assertEquals(40319, failure.code)
            val request = server.takeRequest()
            assertEquals("DELETE", request.method)
            assertEquals("Bearer session-token", request.getHeader("Authorization"))
            assertEquals("DELETE", JSONObject(request.body.readUtf8()).getString("confirmation"))
        }
    }

    @Test
    fun credentialsAreNotForwardedWhenServerRedirects() {
        MockWebServer().use { server ->
            MockWebServer().use { other ->
                other.start()
                server.enqueue(MockResponse().setResponseCode(307).setHeader("Location", other.url("/receive")))
                val api = ApiClient(server.url("/sumly/api/v1/").toString())

                val failure = assertThrows(ApiException::class.java) {
                    runBlocking { api.get("app/auth/me", accessToken = "session-token") }
                }

                assertEquals(307, failure.httpStatus)
                assertEquals(0, other.requestCount)
            }
        }
    }

    @Test
    fun externalAndTraversalPathsAreRejectedBeforeSendingCredentials() {
        MockWebServer().use { server ->
            val api = ApiClient(server.url("/sumly/api/v1/").toString())
            for (path in listOf("https://example.com/app/auth", "../auth", "/app/auth", "app/%2e%2e/auth")) {
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { api.get(path, accessToken = "session-token") }
                }
            }
            assertEquals(0, server.requestCount)
        }
    }

    @Test
    fun holdingsPutPreservesInt64RevisionAndBearer() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"code":0,"data":{"revision":9007199254740994}}"""))
            val api = ApiClient(server.url("/sumly/api/v1/").toString())
            val body = JSONObject().put("expectedRevision", 9_007_199_254_740_993L)

            assertEquals(9_007_199_254_740_994L, api.put("app/holdings", body, "account-token").getLong("revision"))
            val request = server.takeRequest()
            assertEquals("PUT", request.method)
            assertEquals("/sumly/api/v1/app/holdings", request.path)
            assertEquals("Bearer account-token", request.getHeader("Authorization"))
            assertEquals(9_007_199_254_740_993L, JSONObject(request.body.readUtf8()).getLong("expectedRevision"))
        }
    }

    @Test
    fun holdingsRejectsAnOversizedChunkedResponse() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setChunkedBody("""{"code":0,"data":{"document":"${"a".repeat(256)}"}}""", 16))
            val api = ApiClient(server.url("/sumly/api/v1/").toString())

            val failure = assertThrows(ApiException::class.java) {
                runBlocking { api.get("app/holdings", maxResponseBytes = 80L) }
            }
            assertEquals(413, failure.httpStatus)
        }
    }
}
