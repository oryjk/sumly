package com.oryjk.sumly.features.chanlun

import android.webkit.CookieManager
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal object ChanlunCookies {
    private val writes = Mutex()
    private val cleanup = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var owner: Any? = null

    suspend fun install(
        lease: Any,
        cookie: ChanlunWebCookie,
        isStillActive: () -> Boolean,
    ): Boolean = withContext(Dispatchers.Main.immediate + NonCancellable) {
        writes.withLock {
            if (!isStillActive() || (owner != null && owner !== lease)) return@withLock false
            owner = lease
            val manager = CookieManager.getInstance()
            if (!manager.write(ChanlunWebPolicy.expiredCookie) || !isStillActive()) {
                owner = null
                return@withLock false
            }

            val installed = manager.write(cookie.header)
            if (!installed || !isStillActive()) {
                manager.write(ChanlunWebPolicy.expiredCookie)
                owner = null
                return@withLock false
            }
            true
        }
    }

    fun release(lease: Any) {
        cleanup.launch {
            writes.withLock {
                if (owner !== lease) return@withLock
                try {
                    CookieManager.getInstance().write(ChanlunWebPolicy.expiredCookie)
                } catch (_: RuntimeException) {
                    // WebView may already have terminated. A new lease must clear it before loading.
                } finally {
                    owner = null
                }
            }
        }
    }

    private suspend fun CookieManager.write(value: String): Boolean = suspendCancellableCoroutine { result ->
        try {
            setCookie(ChanlunWebPolicy.cookieUrl, value) { written ->
                if (result.isActive) result.resume(written)
            }
        } catch (_: RuntimeException) {
            if (result.isActive) result.resume(false)
        }
    }
}
