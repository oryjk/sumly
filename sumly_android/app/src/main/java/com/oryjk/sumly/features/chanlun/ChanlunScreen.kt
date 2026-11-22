package com.oryjk.sumly.features.chanlun

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.view.View
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.account.AccountIdentity
import com.oryjk.sumly.features.account.AccountViewModel
import java.io.ByteArrayInputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

@Composable
fun ChanlunScreen(
    account: AccountViewModel,
    api: ApiClient,
    onClose: () -> Unit,
    onSignIn: () -> Unit,
) {
    val session by account.session.state.collectAsStateWithLifecycle()
    val close by rememberUpdatedState(onClose)
    val identity = session.identity
    var launchIdentity by remember { mutableStateOf(identity) }

    BackHandler(onBack = onClose)
    LaunchedEffect(identity) {
        if (launchIdentity != null && launchIdentity != identity) close()
        else if (launchIdentity == null) launchIdentity = identity
    }

    Column(Modifier.fillMaxSize().background(GoldColors.Background)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onClose) { Text("返回") }
            Text("禅观", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 4.dp))
        }
        Box(Modifier.fillMaxSize()) {
            when {
                identity != null && identity == launchIdentity -> key(identity) {
                    ChanlunBrowserContent(account, identity, api)
                }
                launchIdentity != null || session.restoring -> ChanlunLoading()
                else -> Column(
                    modifier = Modifier.align(Alignment.Center).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Text("登录记金后即可打开禅观", style = MaterialTheme.typography.titleMedium)
                    Button(onClick = onSignIn) { Text("登录 / 注册") }
                }
            }
        }
    }
}

private enum class ChanlunPageState { Loading, Ready, Failed }

@Composable
private fun ChanlunBrowserContent(account: AccountViewModel, identity: AccountIdentity, api: ApiClient) {
    val bridge = remember(api) { ChanlunSessionBridge(api) }
    var attempt by remember { mutableIntStateOf(0) }
    key(attempt) {
        val browser = remember { ChanlunBrowser { account.session.state.value.identity == identity } }
        DisposableEffect(browser) {
            onDispose { browser.close() }
        }
        if (browser.state != ChanlunPageState.Failed) {
            AndroidView(
                factory = { browser.create(it) },
                update = { it.visibility = if (browser.state == ChanlunPageState.Ready) View.VISIBLE else View.INVISIBLE },
                onReset = null,
                onRelease = { browser.releaseView(it) },
                modifier = Modifier.fillMaxSize(),
            )
            LaunchedEffect(browser) {
                try {
                    val cookie = bridge.open(account.session, identity)
                    currentCoroutineContext().ensureActive()
                    val installed = ChanlunCookies.install(browser, cookie, browser::isActive)
                    currentCoroutineContext().ensureActive()
                    if (installed && browser.isActive()) browser.load()
                    else browser.fail()
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    browser.fail()
                }
            }
        }
        when (browser.state) {
            ChanlunPageState.Loading -> ChanlunLoading(browser.progress)
            ChanlunPageState.Ready -> Unit
            ChanlunPageState.Failed -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("暂时无法打开禅观")
                    Button(onClick = { attempt++ }) { Text("重试") }
                }
            }
        }
    }
}

@Composable
private fun ChanlunLoading(progress: Float = 0f) {
    Box(Modifier.fillMaxSize()) {
        LinearProgressIndicator(progress = { progress.coerceIn(0.08f, 1f) }, modifier = Modifier.fillMaxWidth())
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 3.dp)
            Text("正在打开禅观…", color = GoldColors.Muted)
        }
    }
}

private class ChanlunBrowser(private val matchesAccount: () -> Boolean) {
    var state by mutableStateOf(ChanlunPageState.Loading)
        private set
    var progress by mutableStateOf(0f)
        private set
    private var view: WebView? = null
    private var rendererGone = false
    @Volatile
    private var closed = false

    fun isActive(): Boolean = !closed && state != ChanlunPageState.Failed && matchesAccount()

    fun create(context: Context): View = try {
        createWebView(context)
    } catch (_: RuntimeException) {
        view?.destroy()
        view = null
        fail()
        View(context)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(context: Context): WebView = WebView(context).also { browser ->
        view = browser
        browser.settings.apply {
            // The same-origin Chanlun H5 is a React app and needs JavaScript. It has no native bridge.
            javaScriptEnabled = true
            domStorageEnabled = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_NO_CACHE
            safeBrowsingEnabled = true
            setGeolocationEnabled(false)
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, false)
        browser.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                if (isActive()) progress = newProgress.coerceIn(0, 100) / 100f
            }

            override fun onPermissionRequest(request: PermissionRequest) = request.deny()
        }
        browser.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !isActive() || !ChanlunWebPolicy.allows(request.url.toString())

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (!closed && matchesAccount() && ChanlunWebPolicy.allows(request.url.toString())) return null
                return WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(byteArrayOf()))
            }

            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                if (!isActive() || !ChanlunWebPolicy.allows(url)) fail()
            }

            override fun onPageFinished(view: WebView, url: String) {
                if (isActive() && ChanlunWebPolicy.allows(url)) state = ChanlunPageState.Ready
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) fail()
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) fail()
            }

            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                fail()
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                rendererGone = true
                state = ChanlunPageState.Failed
                ChanlunCookies.release(this@ChanlunBrowser)
                return true
            }
        }
    }

    fun load() {
        if (isActive()) view?.loadUrl(ChanlunWebPolicy.pageUrl)
    }

    fun fail() {
        if (closed || state == ChanlunPageState.Failed) return
        state = ChanlunPageState.Failed
        view?.stopLoading()
        ChanlunCookies.release(this)
    }

    fun close() {
        if (closed) return
        closed = true
        if (!rendererGone) view?.stopLoading()
        ChanlunCookies.release(this)
    }

    fun releaseView(browser: View) {
        if (browser !is WebView) return
        if (view === browser) view = null
        browser.destroy()
    }
}
