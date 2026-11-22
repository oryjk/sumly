package com.oryjk.sumly.features.chanlun

import java.io.IOException
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChanlunExchangeTest {
    private val ticket = "A".repeat(43)

    @Test
    fun exchangeSendsTicketInPrivateJsonBodyAndNeverForwardsNativeAuthorization() = runBlocking {
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            assertEquals("POST", request.method)
            assertEquals(ChanlunWebPolicy.exchangeUrl, request.url)
            assertNull(request.header("Authorization"))
            assertNull(request.header("Cookie"))
            assertFalse(request.url.toString().contains(ticket))
            val body = Buffer()
            requireNotNull(request.body).writeTo(body)
            assertEquals(ticket, JSONObject(body.readUtf8()).getString("code"))
            response(request, 204)
        }.build()

        assertTrue(ChanlunExchange(http).exchange(ticket).header.startsWith("chanlun_session=payload.signature;"))
    }

    @Test
    fun redirectOrSuccessWithNoCookieNeverOpensBrowserSession() = runBlocking {
        for (status in listOf(200, 302)) {
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                response(chain.request(), status)
            }.build()
            assertTrue(runCatching { ChanlunExchange(http).exchange(ticket) }.exceptionOrNull() is IOException)
        }
        val missingCookie = OkHttpClient.Builder().addInterceptor { chain ->
            response(chain.request(), 204).newBuilder().removeHeader("Set-Cookie").build()
        }.build()
        assertTrue(runCatching { ChanlunExchange(missingCookie).exchange(ticket) }.exceptionOrNull() is IOException)
    }

    private fun response(request: Request, status: Int) = Response.Builder()
        .request(request)
        .protocol(Protocol.HTTP_1_1)
        .code(status)
        .message("fixture")
        .header("Set-Cookie", "chanlun_session=payload.signature; Path=/chanlun/; Secure; HttpOnly")
        .body("".toResponseBody())
        .build()
}
