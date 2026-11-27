package com.oryjk.sumly.features.market

import android.util.AtomicFile
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.core.network.ApiException
import java.io.File
import java.io.IOException
import java.time.Clock
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

interface GoldMarketService {
    suspend fun cachedQuote(basis: MarketBasis): MarketQuote? = null
    suspend fun cachedHistory(basis: MarketBasis): List<MarketObservation> = emptyList()
    suspend fun fetchQuote(basis: MarketBasis): MarketQuote
    suspend fun fetchRealtime(basis: MarketBasis): RealtimeWindow
    suspend fun fetchHistory(basis: MarketBasis, force: Boolean = false): List<MarketObservation>
    suspend fun clearCache() = Unit
}

/** Public market data has its own cache. The API instance and cache folder must share a base URL. */
class BackendGoldMarketService(
    private val api: ApiClient,
    private val cacheDirectory: File? = null,
    private val clock: Clock = Clock.systemUTC(),
) : GoldMarketService {
    private val series = MarketBasis.entries.associateWith { SeriesCache() }

    override suspend fun cachedQuote(basis: MarketBasis): MarketQuote? = withContext(Dispatchers.IO) {
        val cache = series.getValue(basis)
        cache.quoteLock.withLock { readQuote(basis, cache) }
    }

    override suspend fun cachedHistory(basis: MarketBasis): List<MarketObservation> = withContext(Dispatchers.IO) {
        val cache = series.getValue(basis)
        cache.historyLock.withLock { readHistory(basis, cache)?.snapshot?.observations.orEmpty() }
    }

    override suspend fun fetchQuote(basis: MarketBasis): MarketQuote {
        return withContext(Dispatchers.IO) {
            val cache = series.getValue(basis)
            cache.quoteLock.withLock {
                val payload = api.get(basis.quotePath)
                val incoming = MarketPayload.quote(payload)
                val current = readQuote(basis, cache)
                if (current != null && current.asOf > incoming.asOf) return@withLock current
                if (current != incoming) {
                    coroutineContext.ensureActive()
                    cache.quote = incoming
                    writeRecord(basis, "quote", payload)
                }
                incoming
            }
        }
    }

    override suspend fun fetchRealtime(basis: MarketBasis): RealtimeWindow {
        val maxResponseBytes = 4L * 1024 * 1024
        val payload = fetchRealtimePayload(basis.realtimePath, maxResponseBytes)
        return withContext(Dispatchers.Default) { MarketPayload.realtime(payload) }
    }

    private suspend fun fetchRealtimePayload(path: String, maxResponseBytes: Long): JSONObject {
        val attempts = listOf(mapOf("window" to "day"), mapOf("window" to "session"), emptyMap())
        var lastRejected: ApiException? = null
        for (query in attempts) {
            try {
                return api.get(path, query, maxResponseBytes = maxResponseBytes)
            } catch (rejected: ApiException) {
                if (rejected.httpStatus != 400 && rejected.httpStatus != 422) throw rejected
                lastRejected = rejected
            }
        }
        throw checkNotNull(lastRejected)
    }

    override suspend fun fetchHistory(basis: MarketBasis, force: Boolean): List<MarketObservation> =
        withContext(Dispatchers.IO) {
            val cache = series.getValue(basis)
            cache.historyLock.withLock {
                val previous = readHistory(basis, cache)
                val requestedAt = clock.instant()
                if (!force && previous != null) {
                    val age = Duration.between(previous.checkedAt, requestedAt)
                    if (!age.isNegative && age < Duration.ofMinutes(15)) return@withLock previous.snapshot.observations
                }
                val query = buildMap {
                    put("series", basis.series)
                    previous?.let { put("cursor", it.snapshot.cursor) }
                }
                val page = MarketPayload.history(api.get("app/market/gold/sync", query))
                val snapshot = page.merge(basis, previous?.snapshot)
                coroutineContext.ensureActive()
                cache.history = CheckedHistory(snapshot, requestedAt)
                if (cacheDirectory != null) {
                    writeRecord(basis, "history", MarketPayload.historyRecord(basis, snapshot, requestedAt))
                }
                snapshot.observations
            }
        }

    override suspend fun clearCache() = withContext(Dispatchers.IO) {
        series.forEach { (basis, cache) ->
            cache.quoteLock.withLock {
                cache.quote = null
                cacheDirectory?.let { AtomicFile(File(it, "${basis.series}-quote.json")).delete() }
            }
            cache.historyLock.withLock {
                cache.history = null
                cacheDirectory?.let { AtomicFile(File(it, "${basis.series}-history.json")).delete() }
            }
        }
    }

    private fun readQuote(basis: MarketBasis, cache: SeriesCache): MarketQuote? = cache.quote
        ?: readRecord(basis, "quote") { MarketPayload.quote(it) }.also { cache.quote = it }

    private fun readHistory(basis: MarketBasis, cache: SeriesCache): CheckedHistory? = cache.history
        ?: readRecord(basis, "history") { payload ->
            CheckedHistory(
                snapshot = MarketPayload.history(payload).merge(basis, null),
                checkedAt = Instant.ofEpochMilli(payload.getLong("checked_at")),
            )
        }.also { cache.history = it }

    private fun <T> readRecord(basis: MarketBasis, suffix: String, decode: (JSONObject) -> T): T? {
        val directory = cacheDirectory ?: return null
        val file = AtomicFile(File(directory, "${basis.series}-$suffix.json"))
        // Files in this directory can be evicted or left by an older cache format.
        return runCatching { decode(JSONObject(file.readFully().toString(Charsets.UTF_8))) }.getOrNull()
    }

    private fun writeRecord(basis: MarketBasis, suffix: String, payload: JSONObject) {
        val directory = cacheDirectory ?: return
        val file = AtomicFile(File(directory, "${basis.series}-$suffix.json"))
        val stream = try { file.startWrite() } catch (_: IOException) { return }
        try {
            stream.write(payload.toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (_: IOException) {
            file.failWrite(stream)
        }
    }

    private data class CheckedHistory(val snapshot: HistorySnapshot, val checkedAt: Instant)

    private class SeriesCache {
        val quoteLock = Mutex()
        val historyLock = Mutex()
        var quote: MarketQuote? = null
        var history: CheckedHistory? = null
    }
}
