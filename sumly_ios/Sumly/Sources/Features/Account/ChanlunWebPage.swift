import SwiftUI
import WebKit

struct ChanlunWebConfiguration: Equatable, Sendable {
    let pageURL: URL

    static let current: Self? = {
        if let url = SumlyInternalTestEnvironment.chanlunURL { return Self(rawURL: url.absoluteString) }
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SUMLY_CHANLUN_WEB_URL"] {
            return Self(rawURL: raw)
        }
        #endif
        return nil
    }()

    init?(rawURL: String) {
        guard var components = URLComponents(string: rawURL),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        if components.scheme != "https" {
            #if DEBUG
            guard components.scheme == "http", ["localhost", "127.0.0.1"].contains(host) else { return nil }
            #else
            return nil
            #endif
        }
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { return nil }
        pageURL = url
    }

    var exchangeURL: URL { pageURL.appendingPathComponent("api/auth/sumly/session") }

    func allows(_ url: URL) -> Bool {
        let defaultPort = pageURL.scheme == "https" ? 443 : 80
        guard url.scheme == pageURL.scheme, url.host == pageURL.host,
              (url.port ?? defaultPort) == (pageURL.port ?? defaultPort),
              url.user == nil, url.password == nil else { return false }
        guard !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { return false }
        let base = pageURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return base.isEmpty || url.path == "/" + base || url.path.hasPrefix("/" + base + "/")
    }
}

private struct ChanlunTicket: Codable, Sendable { let code: String }

private final class ChanlunExchangeDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

@MainActor @Observable final class ChanlunWebSession: NSObject, WKNavigationDelegate {
    private let configuration: ChanlunWebConfiguration
    let webView: WKWebView
    private(set) var loading = true
    private(set) var failed = false

    init(configuration: ChanlunWebConfiguration) {
        self.configuration = configuration
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        super.init()
        webView.navigationDelegate = self
        // The H5 tab bar handles the bottom safe area through viewport-fit=cover.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    func open(using session: AuthSession) async throws {
        loading = true
        failed = false
        let generation = session.sessionGeneration
        let ticket = try await session.authorized(ChanlunTicket.self) { token in
            AuthRequest(path: "chanlun/session", bearer: token)
        }
        try Task.checkCancellation()
        let cookie = try await exchange(ticket)
        try Task.checkCancellation()
        guard generation == session.sessionGeneration else { throw AuthError.stale }
        await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        try Task.checkCancellation()
        guard generation == session.sessionGeneration else { throw AuthError.stale }
        webView.load(URLRequest(url: configuration.pageURL))
    }

    private func exchange(_ ticket: ChanlunTicket) async throws -> HTTPCookie {
        let endpoint = configuration.exchangeURL
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = try JSONEncoder().encode(ticket)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let transport = URLSessionConfiguration.ephemeral
        transport.httpShouldSetCookies = false
        let network = URLSession(configuration: transport)
        defer { network.invalidateAndCancel() }
        let (_, response) = try await network.data(for: request, delegate: ChanlunExchangeDelegate())
        guard let http = response as? HTTPURLResponse, http.statusCode == 204, http.url == endpoint,
              let header = http.value(forHTTPHeaderField: "Set-Cookie"),
              let cookie = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: endpoint).first(where: {
                  $0.name == "chanlun_session" && $0.domain == endpoint.host && $0.isHTTPOnly &&
                  (endpoint.scheme != "https" || $0.isSecure)
              }) else { throw AuthError.malformed }
        return cookie
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, configuration.allows(url) else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let result = navigationResponse.response as? HTTPURLResponse,
           !(200..<300).contains(result.statusCode) {
            showError()
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError() }

    func showError() {
        loading = false
        failed = true
    }
}

struct ChanlunWebPage: View {
    let session: AuthSession
    @Environment(\.dismiss) private var dismiss
    @State private var webSession: ChanlunWebSession
    @State private var attempt = 0

    init(configuration: ChanlunWebConfiguration, session: AuthSession) {
        self.session = session
        _webSession = State(initialValue: ChanlunWebSession(configuration: configuration))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ChanlunWebContent(webView: webSession.webView)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .opacity(webSession.loading || webSession.failed ? 0 : 1)
                if webSession.loading {
                    ProgressView("正在打开禅观…")
                } else if webSession.failed {
                    VStack(spacing: 16) {
                        Text("暂时无法打开禅观")
                        Button("重试") { attempt += 1 }
                    }
                }
            }
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle("禅观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GoldTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("chanlun.back")
                }
            }
        }
        .task(id: attempt) {
            do { try await webSession.open(using: session) }
            catch {
                if !Task.isCancelled { webSession.showError() }
            }
        }
        .onChange(of: session.sessionGeneration) { dismiss() }
        .onDisappear { webSession.webView.stopLoading() }
    }
}

private struct ChanlunWebContent: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
