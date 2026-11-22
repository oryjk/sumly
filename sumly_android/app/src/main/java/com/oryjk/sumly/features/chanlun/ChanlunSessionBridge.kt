package com.oryjk.sumly.features.chanlun

import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.features.account.AccountIdentity
import com.oryjk.sumly.features.account.AuthSession
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject

internal class ChanlunSessionBridge(
    private val api: ApiClient,
    private val exchange: ChanlunExchange = ChanlunExchange(),
) {
    suspend fun open(session: AuthSession, identity: AccountIdentity): ChanlunWebCookie {
        val ticket = session.authorized(identity) { token ->
            api.post("app/auth/chanlun/session", JSONObject(), accessToken = token).getString("code")
        }
        return exchange.exchange(ticket)
    }
}

internal class ChanlunExchange(
    private val http: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(12, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .build(),
) {
    suspend fun exchange(ticket: String): ChanlunWebCookie {
        if (!TicketPattern.matches(ticket)) throw IOException("Invalid Chanlun ticket.")
        val endpoint = ChanlunWebPolicy.exchangeUrl
        val body = JSONObject().put("code", ticket).toString().toRequestBody(JsonType)
        val request = Request.Builder().url(endpoint).post(body).header("Cache-Control", "no-store").build()
        return suspendCancellableCoroutine { continuation ->
            val call = http.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) continuation.resumeWithException(IOException("Chanlun exchange failed."))
                }

                override fun onResponse(call: Call, response: Response) {
                    val cookie = response.use {
                        if (it.code != 204 || it.request.url != endpoint) null
                        else ChanlunWebPolicy.cookieFrom(it.headers("Set-Cookie"))
                    }
                    if (!continuation.isActive) return
                    if (cookie == null) {
                        continuation.resumeWithException(IOException("Invalid Chanlun session response."))
                    } else {
                        continuation.resumeWith(Result.success(cookie))
                    }
                }
            })
        }
    }

    private companion object {
        val TicketPattern = Regex("[A-Za-z0-9_-]{43}")
        val JsonType = "application/json".toMediaType()
    }
}
