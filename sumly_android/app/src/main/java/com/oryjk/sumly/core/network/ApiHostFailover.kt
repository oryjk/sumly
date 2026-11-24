package com.oryjk.sumly.core.network

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import okhttp3.HttpUrl
import retrofit2.Response
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ProtocolException
import java.net.SocketException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

/** Process-wide routing for the two configured production API origins. */
internal class ApiHostFailover(
    val primary: HttpUrl,
    private val backup: HttpUrl,
    private val elapsedMs: () -> Long = { TimeUnit.NANOSECONDS.toMillis(System.nanoTime()) },
) {
    private data class Selection(val url: HttpUrl, val generation: Long)

    private var preferred = primary
    private var nextProbeMs = 0L
    private var generation = 0L

    suspend fun <T> send(safeRead: Boolean, transfer: suspend (HttpUrl) -> Response<T>): Response<T> {
        currentCoroutineContext().ensureActive()
        val first = select(safeRead)
        if (!safeRead) return transfer(first.url)

        val initial = try {
            transfer(first.url)
        } catch (error: IOException) {
            currentCoroutineContext().ensureActive()
            if (!isConnectivityFailure(error)) throw error
            null
        }
        if (initial != null && !isGatewayFailure(initial.code())) {
            currentCoroutineContext().ensureActive()
            noteResponse(first.url, first.generation)
            return initial
        }

        initial?.errorBody()?.close()
        currentCoroutineContext().ensureActive()
        val alternate = if (first.url == primary) backup else primary
        val response = transfer(alternate)
        currentCoroutineContext().ensureActive()
        if (!isGatewayFailure(response.code())) noteResponse(alternate, first.generation)
        return response
    }

    @Synchronized
    private fun select(safeRead: Boolean): Selection {
        if (preferred == primary) return Selection(primary, generation)
        val now = elapsedMs()
        if (!safeRead || now < nextProbeMs) return Selection(backup, generation)
        // While this probe runs, other requests keep using the last responding origin.
        nextProbeMs = now + ProbeIntervalMs
        return Selection(primary, generation)
    }

    @Synchronized
    private fun noteResponse(origin: HttpUrl, startedAtGeneration: Long) {
        // A late response from an older route should not undo a more recent switch.
        if (generation != startedAtGeneration || preferred == origin) return
        preferred = origin
        generation++
        if (origin == backup) nextProbeMs = elapsedMs() + ProbeIntervalMs
    }

    private fun isGatewayFailure(status: Int): Boolean = status == 502 || status == 503 || status == 504

    // OkHttp wraps a truncated response header in IOException. A Gson EOFException alone
    // means the complete HTTP body contained incomplete JSON.
    private fun isConnectivityFailure(error: IOException): Boolean =
        generateSequence<Throwable>(error) { it.cause }.any {
            it is SocketException || it is UnknownHostException || it is InterruptedIOException ||
                it is SSLException || it is ProtocolException || (it.javaClass == IOException::class.java && it.cause is EOFException)
        }

    private companion object {
        const val ProbeIntervalMs = 60_000L
    }
}
