package com.oryjk.sumly.core.network

import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParseException
import com.google.gson.JsonParser
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.buffer
import org.json.JSONObject
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.HTTP
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.QueryMap
import retrofit2.http.Tag
import retrofit2.http.Url
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(val httpStatus: Int, val code: Int, message: String) : IOException(message)

/** Shared transport for the app API, including the path prefix used by the production proxy. */
class ApiClient internal constructor(url: HttpUrl, private val failover: ApiHostFailover?) {
    private val routes: AppRoutes

    constructor(baseUrl: String = DefaultBaseUrl) : this((baseUrl.trimEnd('/') + "/").toHttpUrl())

    private constructor(url: HttpUrl) : this(url, productionFailover.takeIf { url == it.primary })

    init {
        require(url.isHttps || url.host in loopbackHosts) { "The API requires HTTPS outside loopback." }
        require(url.encodedUsername.isEmpty() && url.encodedPassword.isEmpty())
        require(url.query == null && url.fragment == null)

        val httpBuilder = OkHttpClient.Builder()
            .callTimeout(20, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .addInterceptor { chain ->
                val request = chain.request()
                val response = chain.proceed(request.newBuilder().header("Accept", "application/json").build())
                val limit = request.tag(ResponseSizeLimit::class.java)
                val body = response.body
                if (limit == null || body == null) {
                    response
                } else {
                    if (body.contentLength() > limit.bytes) {
                        response.close()
                        throw oversizedResponse()
                    }
                    response.newBuilder().body(BoundedResponseBody(body, limit.bytes)).build()
                }
            }
        if (failover != null) {
            httpBuilder.addNetworkInterceptor { chain ->
                val response = chain.proceed(chain.request())
                // OkHttp can replay a 503 with Retry-After: 0 even with connection retries disabled.
                if (response.code == 503) response.newBuilder().removeHeader("Retry-After").build() else response
            }
        }

        routes = Retrofit.Builder()
            .baseUrl(url)
            .client(httpBuilder.build())
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(AppRoutes::class.java)
    }

    suspend fun get(
        path: String,
        query: Map<String, String> = emptyMap(),
        accessToken: String? = null,
        maxResponseBytes: Long? = null,
    ): JSONObject = request(path, safeRead = true) { route ->
        routes.get(route, query, authorization(accessToken), maxResponseBytes?.let(::ResponseSizeLimit))
    }

    suspend fun post(path: String, body: JSONObject, accessToken: String? = null): JSONObject =
        request(path) { route ->
            routes.post(route, JsonParser.parseString(body.toString()).asJsonObject, authorization(accessToken))
        }

    suspend fun put(
        path: String,
        body: JSONObject,
        accessToken: String? = null,
        maxResponseBytes: Long? = null,
    ): JSONObject = request(path) { route ->
        routes.put(
            route, JsonParser.parseString(body.toString()).asJsonObject,
            authorization(accessToken), maxResponseBytes?.let(::ResponseSizeLimit),
        )
    }

    suspend fun delete(path: String, accessToken: String? = null, body: JSONObject? = null): JSONObject = request(path) { route ->
        val header = authorization(accessToken)
        if (body == null) routes.delete(route, header)
        else routes.deleteWithBody(route, JsonParser.parseString(body.toString()).asJsonObject, header)
    }

    private suspend fun request(
        path: String,
        safeRead: Boolean = false,
        call: suspend (String) -> Response<JsonObject>,
    ): JSONObject {
        val route = checkedPath(path)
        val response = try {
            failover?.send(safeRead) { origin -> call(checkNotNull(origin.resolve(route)).toString()) }
                ?: call(route)
        } catch (_: JsonParseException) {
            throw ApiException(0, -1, "服务返回格式异常。")
        }
        val status = response.code()
        val envelope = if (response.isSuccessful) {
            response.body()
        } else {
            response.errorBody()?.use { body ->
                try {
                    JsonParser.parseReader(body.charStream()).takeIf(JsonElement::isJsonObject)?.asJsonObject
                } catch (_: JsonParseException) {
                    null
                }
            }
        }
        val code = envelope?.get("code")?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isNumber }
            ?.asString?.toIntOrNull() ?: -1
        if (!response.isSuccessful || code != 0) {
            val message = envelope?.get("message")?.takeIf { it.isJsonPrimitive && it.asJsonPrimitive.isString }
                ?.asString?.trim()?.take(300)?.takeIf(String::isNotEmpty)
            throw ApiException(status, code, message ?: "服务请求失败。")
        }

        val data = envelope?.get("data")
        if (data == null || data.isJsonNull) return JSONObject()
        if (!data.isJsonObject) throw ApiException(status, -1, "服务返回格式异常。")
        return JSONObject(data.toString())
    }

    private fun checkedPath(path: String): String {
        require(relativePath.matches(path)) { "Use a relative app API route." }
        return path
    }

    private fun authorization(token: String?): String? = token?.let { "Bearer $it" }

    private interface AppRoutes {
        @GET
        suspend fun get(
            @Url path: String,
            @QueryMap query: Map<String, String>,
            @Header("Authorization") authorization: String?,
            @Tag limit: ResponseSizeLimit?,
        ): Response<JsonObject>

        @POST
        suspend fun post(
            @Url path: String,
            @Body body: JsonObject,
            @Header("Authorization") authorization: String?,
        ): Response<JsonObject>

        @PUT
        suspend fun put(
            @Url path: String,
            @Body body: JsonObject,
            @Header("Authorization") authorization: String?,
            @Tag limit: ResponseSizeLimit?,
        ): Response<JsonObject>

        @DELETE
        suspend fun delete(@Url path: String, @Header("Authorization") authorization: String?): Response<JsonObject>

        @HTTP(method = "DELETE", hasBody = true)
        suspend fun deleteWithBody(
            @Url path: String,
            @Body body: JsonObject,
            @Header("Authorization") authorization: String?,
        ): Response<JsonObject>
    }

    companion object {
        private const val DefaultSiteUrl = "https://oryjk.cn/sumly/"
        const val DefaultBaseUrl = "${DefaultSiteUrl}api/v1/"
        const val DefaultPrivacyPolicyUrl = "${DefaultSiteUrl}privacy"
        private const val BackupBaseUrl = "https://backup.oryjk.cn:19443/sumly/api/v1/"
        private const val HomeBaseUrl = "https://home.oryjk.cn:18443/sumly/api/v1/"
        private val productionFailover = ApiHostFailover(DefaultBaseUrl.toHttpUrl(), BackupBaseUrl.toHttpUrl(), HomeBaseUrl.toHttpUrl())
        private val loopbackHosts = setOf("localhost", "127.0.0.1", "::1")
        private val relativePath = Regex("app(?:/[A-Za-z0-9_-]+)+")
    }
}

private class ResponseSizeLimit(val bytes: Long) {
    init { require(bytes > 0) }
}

private class BoundedResponseBody(private val delegate: ResponseBody, limit: Long) : ResponseBody() {
    private val stream = object : ForwardingSource(delegate.source()) {
        private var remaining = limit

        override fun read(sink: Buffer, byteCount: Long): Long {
            val read = super.read(sink, if (remaining >= byteCount) byteCount else remaining + 1)
            if (read > remaining) throw oversizedResponse()
            if (read > 0) remaining -= read
            return read
        }
    }.buffer()

    override fun contentLength(): Long = delegate.contentLength()
    override fun contentType(): MediaType? = delegate.contentType()
    override fun source(): BufferedSource = stream
}

private fun oversizedResponse() = ApiException(413, 413, "服务返回的数据超过大小限制。")
