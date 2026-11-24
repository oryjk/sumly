package com.oryjk.sumly.core.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.TimeUnit

class ApiHostFailoverTest {
    @Test
    fun gatewayFailurePreservesRequestAndKeepsBackupUntilSafePrimaryProbe() = runBlocking {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                var elapsedMs = 0L
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl) { elapsedMs })
                main.enqueue(MockResponse().setResponseCode(503).setHeader("Retry-After", "0"))
                main.enqueue(ok("main"))
                main.enqueue(ok("main"))
                repeat(3) { backup.enqueue(ok("backup")) }

                val path = "app/holdings"
                val first = api.get(path, mapOf("basis" to "上海 黄金+"), "session-token")
                assertEquals("backup", first.getString("host"))
                assertEquals("backup", api.get(path).getString("host"))
                elapsedMs = 61_000L
                assertEquals("backup", api.put(path, JSONObject().put("revision", 1)).getString("host"))
                assertEquals("main", api.get(path).getString("host"))
                assertEquals("main", api.get(path).getString("host"))

                val initial = main.takeRequest()
                val retried = backup.takeRequest()
                assertEquals("/sumly/api/v1/app/holdings", retried.requestUrl?.encodedPath)
                assertEquals("上海 黄金+", retried.requestUrl?.queryParameter("basis"))
                assertEquals(initial.path, retried.path)
                assertEquals("Bearer session-token", retried.getHeader("Authorization"))
                assertEquals(3, main.requestCount)
                assertEquals(3, backup.requestCount)
                backup.takeRequest()
                assertEquals("PUT", backup.takeRequest().method)
            }
        }
    }

    @Test
    fun aRefusedConnectionRetriesOnBackup() = runBlocking {
        MockWebServer().use { backup ->
            val backupUrl = backup.url("/sumly/api/v1/")
            backup.enqueue(ok("backup"))
            val unusedPort = ServerSocket(0, 0, InetAddress.getByName("127.0.0.1")).use { it.localPort }
            val primaryUrl = "http://127.0.0.1:$unusedPort/sumly/api/v1/".toHttpUrl()
            val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))

            assertEquals("backup", api.get("app/auth/me").getString("host"))
            assertEquals(1, backup.requestCount)
        }
    }

    @Test
    fun failedBackupStopsAfterTwoAttemptsAndDoesNotBecomePreferred() {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))
                main.enqueue(MockResponse().setResponseCode(504))
                main.enqueue(ok("main"))
                backup.enqueue(MockResponse().setResponseCode(502))

                val error = assertThrows(ApiException::class.java) { runBlocking { api.get("app/auth/me") } }
                assertEquals(502, error.httpStatus)
                assertEquals(1, main.requestCount)
                assertEquals("main", runBlocking { api.get("app/auth/me") }.getString("host"))
                assertEquals(1, backup.requestCount)
            }
        }
    }

    @Test
    fun cancelledRequestDoesNotContactBackup() = runBlocking {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))
                main.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
                val call = launch { api.get("app/auth/me") }
                assertNotNull(withContext(Dispatchers.IO) { main.takeRequest(3, TimeUnit.SECONDS) })
                call.cancelAndJoin()

                assertEquals(0, backup.requestCount)
            }
        }
    }

    @Test
    fun writesAndOrdinaryStatusFailuresAreNeverReplayed() {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))
                for (code in listOf(401, 500)) {
                    main.enqueue(MockResponse().setResponseCode(code))
                    val error = assertThrows(ApiException::class.java) { runBlocking { api.get("app/auth/me") } }
                    assertEquals(code, error.httpStatus)
                }
                main.enqueue(MockResponse().setResponseCode(503).setHeader("Retry-After", "0"))
                main.enqueue(ok("main"))
                val error = assertThrows(ApiException::class.java) {
                    runBlocking { api.post("app/auth/refresh", JSONObject()) }
                }
                assertEquals(503, error.httpStatus)
                assertEquals(3, main.requestCount)
                assertEquals(0, backup.requestCount)
            }
        }
    }

    @Test
    fun disconnectedResponseBodyRetriesOnBackup() = runBlocking {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))
                main.enqueue(ok("main".repeat(64)).setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY))
                backup.enqueue(ok("backup"))

                assertEquals("backup", api.get("app/auth/me").getString("host"))
                assertEquals(1, main.requestCount)
                assertEquals(1, backup.requestCount)
            }
        }
    }

    @Test
    fun malformedJSONDoesNotContactBackup() {
        MockWebServer().use { main ->
            MockWebServer().use { backup ->
                val primaryUrl = main.url("/sumly/api/v1/")
                val backupUrl = backup.url("/sumly/api/v1/")
                val api = ApiClient(primaryUrl, ApiHostFailover(primaryUrl, backupUrl))
                main.enqueue(MockResponse().setBody("""{"code":"""))
                backup.enqueue(ok("backup"))

                assertThrows(IOException::class.java) { runBlocking { api.get("app/auth/me") } }
                assertEquals(0, backup.requestCount)
            }
        }
    }

    private fun ok(host: String) = MockResponse().setBody("""{"code":0,"data":{"host":"$host"}}""")
}
