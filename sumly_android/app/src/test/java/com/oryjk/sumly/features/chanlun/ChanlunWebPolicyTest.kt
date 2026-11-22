package com.oryjk.sumly.features.chanlun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChanlunWebPolicyTest {
    @Test
    fun routesUseTheSameHttpsOriginAndSeparateLaunchQueryFromExchange() {
        assertEquals(
            "https://match.oryjk.cn/chanlun/?secid=600519.SH&timeframe=30m&view=market",
            ChanlunWebPolicy.pageUrl,
        )
        assertEquals(
            "https://match.oryjk.cn/chanlun/api/auth/sumly/session",
            ChanlunWebPolicy.exchangeUrl.toString(),
        )
        assertTrue(ChanlunWebPolicy.allows("https://MATCH.ORYJK.CN:443/chanlun"))
        assertTrue(ChanlunWebPolicy.allows("https://match.oryjk.cn/chanlun/?view=tracking"))
        for (url in listOf(
            "https://match.oryjk.cn/chanlun-other/",
            "https://match.oryjk.cn/chanlun/../foreign/",
            "https://match.oryjk.cn/chanlun/%2e%2e/foreign/",
            "https://match.oryjk.cn/chanlun/%2e%2e%2fforeign/",
            "https://match.oryjk.cn/chanlun/%252fother/",
            "https://match.oryjk.cn:444/chanlun/",
            "https://match.oryjk.cn.bad.example/chanlun/",
            "https://match.oryjk.cn@bad.example/chanlun/",
            "http://match.oryjk.cn/chanlun/",
            "file:///chanlun/",
        )) {
            assertFalse(url, ChanlunWebPolicy.allows(url))
        }
    }

    @Test
    fun onlyExactHostSecureHttpOnlyCookieEntersWebViewAndLifetimeIsSessionOnly() {
        val cookie = ChanlunWebPolicy.cookieFrom(
            listOf("chanlun_session=payload.signature; Path=/; Max-Age=900; Secure; HttpOnly; SameSite=Lax"),
        )
        assertNotNull(cookie)
        assertEquals(
            "chanlun_session=payload.signature; Path=/chanlun/; Secure; HttpOnly; SameSite=Strict",
            cookie?.header,
        )
        assertNull(ChanlunWebPolicy.cookieFrom(listOf("chanlun_session=x; Path=/; HttpOnly")))
        assertNull(ChanlunWebPolicy.cookieFrom(listOf("chanlun_session=x; Path=/; Secure")))
        assertNull(ChanlunWebPolicy.cookieFrom(listOf(
            "chanlun_session=x; Domain=oryjk.cn; Path=/; Secure; HttpOnly",
        )))
        assertNull(ChanlunWebPolicy.cookieFrom(listOf(
            "chanlun_session=x; Path=/elsewhere; Secure; HttpOnly",
        )))
        assertNull(ChanlunWebPolicy.cookieFrom(listOf(
            "chanlun_session=x; Path=/; Max-Age=0; Secure; HttpOnly",
        )))
        assertNull(ChanlunWebPolicy.cookieFrom(listOf(
            "chanlun_session=x; Path=/; Secure; HttpOnly",
            "chanlun_session=y; Path=/; Secure; HttpOnly",
        )))
    }
}
