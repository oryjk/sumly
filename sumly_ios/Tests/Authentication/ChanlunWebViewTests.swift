import Foundation
import Testing
import WebKit
@testable import Sumly

@Test func chanlunWebViewRestrictsNavigationToConfiguredOrigin() throws {
    let config = try #require(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/"))
    #expect(config.exchangeURL.absoluteString == "https://match.oryjk.cn/chanlun/api/auth/sumly/session")
    #expect(config.allows(URL(string: "https://match.oryjk.cn/chanlun/?view=tracking")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn/other/")!))
    #expect(!config.allows(URL(string: "https://match.oryjk.cn:444/chanlun/")!))
    #expect(!config.allows(URL(string: "https://other.oryjk.cn/chanlun/")!))
    #expect(ChanlunWebConfiguration(rawURL: "http://match.oryjk.cn/chanlun/") == nil)
    #expect(ChanlunWebConfiguration(rawURL: "https://match.oryjk.cn/chanlun/?code=private") == nil)
}

@MainActor private final class ChanlunFixtureStore: CredentialStoring {
    var stored: StoredSession?
    func load() throws -> StoredSession? { stored }
    func save(_ session: StoredSession) throws { stored = session }
    func clear() throws { stored = nil }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SUMLY_CHANLUN_FIXTURE_PASSWORD"] != nil))
@MainActor func local233ChanlunWebViewUsesNativeLogin() async throws {
    let password = try #require(ProcessInfo.processInfo.environment["SUMLY_CHANLUN_FIXTURE_PASSWORD"])
    let authURL = SumlyInternalTestEnvironment.apiBaseURL ?? URL(string: "http://127.0.0.1:18190/api/v1")!
    let configuration = try #require(ChanlunWebConfiguration.current ?? ChanlunWebConfiguration(rawURL: "http://127.0.0.1:18173/chanlun/"))
    if ProcessInfo.processInfo.environment["SUMLY_CHANLUN_REQUIRE_PUBLIC"] == "1" {
        #expect(authURL.scheme == "https" && authURL.port == 82)
        #expect(configuration.pageURL.host == "ai.oryjk.cn")
        #expect(!SumlyInternalTestEnvironment.storageSuffix.isEmpty)
        #expect(SumlyInternalTestEnvironment.defaults !== UserDefaults.standard)
    }
    let session = AuthSession(service: NativeAuthService(baseURL: authURL), store: ChanlunFixtureStore())
    try await session.login(.emailLogin(email: "chanlun-fixture-a@example.test", password: password))
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
