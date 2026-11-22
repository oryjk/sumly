package com.oryjk.sumly.features.chanlun

import java.net.URI
import java.util.Locale
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl

internal class ChanlunWebCookie(val header: String)

internal object ChanlunWebPolicy {
    private const val Host = "match.oryjk.cn"
    private const val Path = "/chanlun/"
    private const val CookieName = "chanlun_session"
    private const val CookieAttributes = "Path=/chanlun/; Secure; HttpOnly; SameSite=Strict"
    private val cookieValue = Regex("[A-Za-z0-9_.-]{1,4000}")
    private val unsafePathEscapes = Regex("%(?:2f|5c|25)")

    const val cookieUrl = "https://$Host$Path"
    const val expiredCookie = "$CookieName=; Max-Age=0; $CookieAttributes"
    const val pageUrl = "${cookieUrl}?secid=600519.SH&timeframe=30m&view=market"
    val exchangeUrl = "${cookieUrl}api/auth/sumly/session".toHttpUrl()
    private val page = pageUrl.toHttpUrl()

    fun allows(rawUrl: String): Boolean {
        val url = try {
            URI(rawUrl)
        } catch (_: java.net.URISyntaxException) {
            return false
        }
        if (!"https".equals(url.scheme, ignoreCase = true) ||
            !Host.equals(url.host, ignoreCase = true) ||
            (url.port != -1 && url.port != 443) || url.rawUserInfo != null
        ) return false

        val path = url.rawPath ?: return false
        if (unsafePathEscapes.containsMatchIn(path.lowercase(Locale.ROOT))) return false
        if (url.path.split('/').any { it == "." || it == ".." }) return false
        return path == Path.dropLast(1) || path.startsWith(Path)
    }

    fun cookieFrom(headers: List<String>, nowMillis: Long = System.currentTimeMillis()): ChanlunWebCookie? {
        val candidates = headers.mapNotNull { Cookie.parse(exchangeUrl, it) }.filter { it.name == CookieName }
        val cookie = candidates.singleOrNull() ?: return null
        if (cookie.domain != Host || !cookie.secure || !cookie.httpOnly ||
            !cookie.matches(page) || cookie.expiresAt <= nowMillis || !cookieValue.matches(cookie.value)
        ) return null

        // Restrict the transferred cookie to this host and path and omit persistence attributes.
        return ChanlunWebCookie("$CookieName=${cookie.value}; $CookieAttributes")
    }
}
