#if os(iOS)
import Foundation
import Testing
import WebKit
@testable import Sumly

@Test(.enabled(if: ProcessInfo.processInfo.environment["SUMLY_CHANLUN_WEB_URL"] == nil))
func chanlunWebViewOpensProductionMarketByDefault() throws {
    let config = try #require(ChanlunWebConfiguration.current)
    #expect(config.pageURL.absoluteString == "https://match.oryjk.cn/chanlun/?secid=600519.SH&timeframe=30m&view=market")
    #expect(config.exchangeURL.absoluteString == "https://match.oryjk.cn/chanlun/api/auth/sumly/session")
}

@Test func chanlunWebViewKeepsInitialQueryOutOfExchange() throws {
    let config = try #require(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun?secid=600519.SH&timeframe=30m&view=market"))
    #expect(config.pageURL.absoluteString == "https://match.oryjk.cn/chanlun/?secid=600519.SH&timeframe=30m&view=market")
    #expect(config.exchangeURL.absoluteString == "https://match.oryjk.cn/chanlun/api/auth/sumly/session")
    #expect(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/?view=market&code=private") == nil)
    #expect(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/?view=market&view=tracking") == nil)
    #expect(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/?view") == nil)
}

@Test func chanlunWebViewRestrictsNavigationToConfiguredOrigin() throws {
    let config = try #require(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/"))
    #expect(config.exchangeURL.absoluteString == "https://match.oryjk.cn/chanlun/api/auth/sumly/session")
    #expect(config.allows(URL(string: "https://match.oryjk.cn/chanlun/?view=tracking")!))
    #expect(config.allows(URL(string: "https://MATCH.ORYJK.CN:443/chanlun")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn/other/")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn/chanlun-other/")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn/chanlun/%2e%2e/other/")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn/chanlun/%2e%2e%2fother/")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn:444/chanlun/")!))
    #expect(!config.allows(URL(string: "https://other.oryjk.cn/chanlun/")!))
    #expect(ChanlunWebConfiguration(rawURL: "http://match.oryjk.cn/chanlun/") == nil)
    #expect(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/?code=private") == nil)
}

#if DEBUG
@Test func chanlunWebViewSupportsLoopbackOverrides() throws {
    let config = try #require(ChanlunWebConfiguration(rawURL: "http://127.0.0.1:5173/"))
    #expect(config.pageURL.absoluteString == "http://127.0.0.1:5173/")
    #expect(config.exchangeURL.absoluteString == "http://127.0.0.1:5173/api/auth/sumly/session")
    #expect(config.allows(URL(string: "http://127.0.0.1:5173/other/")!))
    #expect(!config.allows(URL(string: "http://127.0.0.1:5174/other/")!))
}
#endif

@MainActor private final class ChanlunFixtureStore: CredentialStoring {
    var stored: StoredSession?
    func load() throws -> StoredSession? { stored }
    func save(_ session: StoredSession) throws { stored = session }
    func clear() throws { stored = nil }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SUMLY_CHANLUN_SMOKE_EMAIL"] != nil &&
               ProcessInfo.processInfo.environment["SUMLY_CHANLUN_SMOKE_PASSWORD"] != nil))
@MainActor func chanlunWebViewUsesNativeLogin() async throws {
    let email = try #require(ProcessInfo.processInfo.environment["SUMLY_CHANLUN_SMOKE_EMAIL"])
    let password = try #require(ProcessInfo.processInfo.environment["SUMLY_CHANLUN_SMOKE_PASSWORD"])
    let configuration = try #require(ChanlunWebConfiguration.current)
    let session = AuthSession(service: NativeAuthService(baseURL: BackendGoldPriceService.defaultBaseURL), store: ChanlunFixtureStore())
    try await session.login(.emailLogin(email: email, password: password))
    let user = try #require(session.user)
    let page = ChanlunWebSession(configuration: configuration)
    try await page.open(using: session)
    for _ in 0..<240 where page.loading { try await Task.sleep(for: .milliseconds(100)) }
    #expect(!page.loading && !page.failed)
    #expect(page.webView.url == configuration.pageURL)
    let identity = try await page.webView.callAsyncJavaScript("""
        const session = await fetch('api/auth/session').then(response => response.json());
        return session.authenticated && session.user.user_id;
        """, arguments: [:], in: nil, contentWorld: .page)
    #expect(identity as? String == "sumly:\(user.id)")
    let canReadCookie = try await page.webView.evaluateJavaScript("document.cookie.includes('chanlun_session=')")
    #expect(canReadCookie as? Bool == false)
    let rendered = try await page.webView.evaluateJavaScript("Boolean(document.getElementById('root')?.firstElementChild)")
    #expect(rendered as? Bool == true)
}
#endif
