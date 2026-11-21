import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct SumlyApp: App {
    /// 旧游客持仓容器；登录账户另有隔离的离线缓存。
    private static let holdingsContainer: ModelContainer = {
        do {
            if HoldingsDesignPreview.isEnabled { return try HoldingsDesignPreview.container() }
            return try ModelContainer(for: HoldingRecord.self)
        } catch {
            fatalError("无法初始化本地持仓存储: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            GoldRootView(guestContainer: Self.holdingsContainer)
                .tint(GoldTheme.gold)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.holdingsContainer)
    }
}


private struct GoldRootView: View {
    let guestContainer: ModelContainer
    @State private var session = AuthSession(service: NativeAuthService(baseURL: BackendGoldPriceService.defaultBaseURL), store: KeychainCredentialStore())
    @State private var selectedTab = HoldingsDesignPreview.isEnabled ? 1 : 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HoldingWorkspaceShell(session: session, guestContainer: guestContainer, selectedTab: $selectedTab)
            .id(session.user?.id ?? 0)
            .task {
                await session.restore()
                await session.checkAppleCredential(using: SystemAppleCredentialChecker())
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task {
                    await session.restore()
                    await session.checkAppleCredential(using: SystemAppleCredentialChecker())
                } }
            }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                if session.stored?.appleUserID != nil {
                    session.clearLocal()
                    session.notice = "Apple 授权已撤销，请重新登录。"
                }
            }
    }
}

private struct HoldingWorkspaceShell: View {
    let session: AuthSession
    let guestContainer: ModelContainer
    @Binding var selectedTab: Int
    @State private var cloud: HoldingsCloud?
    @State private var storageError: String?
    var body: some View {
        Group {
            if let cloud {
                GoldWorkspaceView(session: session, cloud: cloud, selectedTab: $selectedTab)
                    .modelContainer(cloud.container)
                    .defaultAppStorage(cloud.defaults)
            } else if let storageError {
                VStack(spacing: 16) {
                    Text("无法打开持仓缓存").font(.headline)
                    Text(storageError).font(.footnote)
                    Button("重试") { openWorkspace() }
                }.padding().foregroundStyle(GoldTheme.text)
            } else { ProgressView("正在打开持仓…") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(GoldTheme.background)
            .task { openWorkspace() }
    }
    private func openWorkspace() {
        do { cloud = try HoldingsCloud(session: session, guestContainer: guestContainer); storageError = nil }
        catch { storageError = error.localizedDescription }
    }
}

private struct GoldWorkspaceView: View {
    @Bindable var session: AuthSession
    let cloud: HoldingsCloud
    @Binding var selectedTab: Int
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("market.basis") private var marketBasisRaw = GoldMarketBasis.domestic.rawValue
    @AppStorage("holdings.currentBook") private var currentBook = "默认账本"
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @State private var quoteStore = LiveGoldQuoteStore()
    @State private var showingAdd = false
    @State private var showingLoginForChanlun = false
    @State private var showingChanlun = false

    private var marketBasis: GoldMarketBasis {
        GoldMarketBasis(rawValue: marketBasisRaw) ?? .domestic
    }

    private var marketBasisBinding: Binding<GoldMarketBasis> {
        Binding(
            get: { GoldMarketBasis(rawValue: marketBasisRaw) ?? .domestic },
            set: { marketBasisRaw = $0.rawValue }
        )
    }

    private func openChanlun() {
        guard ChanlunWebConfiguration.current != nil else { return }
        if session.user == nil {
            showingLoginForChanlun = true
        } else {
            showingChanlun = true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let tabBarLayout = GoldTabBarLayout.resolve(
                containerWidth: geometry.size.width,
                safeAreaBottom: geometry.safeAreaInsets.bottom
            )
            ZStack(alignment: .bottom) {
                GoldTheme.background.ignoresSafeArea()

                // Keep all 4 primary tabs alive so switching tabs preserves scroll, navigation stacks, and chart state.
                ZStack {
                    HomeView(
                        marketBasis: marketBasisBinding,
                        quoteStore: quoteStore,
                        bottomTabBarInset: tabBarLayout.homeAdditionalBottomInset,
                        onOpenHoldings: { selectedTab = 1 },
                        onOpenChanlun: openChanlun
                    )
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                    .accessibilityHidden(selectedTab != 0)

                    HoldingsView(
                        marketBasis: marketBasis,
                        cloud: cloud,
                        quoteStore: quoteStore,
                        onOpenCalendar: { selectedTab = 2 }
                    )
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                    .accessibilityHidden(selectedTab != 1)

                    HoldingsCalendarSheet(
                        initialBook: currentBook,
                        hideAmounts: hideAmounts,
                        marketBasis: marketBasis,
                        quoteStore: quoteStore,
                        isEmbeddedTab: true
                    )
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
                    .accessibilityHidden(selectedTab != 2)

                    AccountView(
                        session: session,
                        cloud: cloud,
                        onOpenChanlun: openChanlun
                    )
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
                    .accessibilityHidden(selectedTab != 3)
                }
                .environment(\.goldTabBarAdditionalBottomInset, tabBarLayout.additionalSafeAreaBottomInset)

                GoldFloatingTabBar(
                    selectedTab: $selectedTab,
                    layout: tabBarLayout,
                    onAdd: { showingAdd = true }
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(
                defaultUnitPrice: quoteStore.quote(for: marketBasis)?.cnyPerGram,
                marketBasis: marketBasis
            )
        }
        .sheet(isPresented: $showingLoginForChanlun) {
            AuthenticationSheet(session: session)
        }
        .fullScreenCover(isPresented: $showingChanlun) {
            if let configuration = ChanlunWebConfiguration.current {
                ChanlunWebPage(configuration: configuration, session: session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketCacheCleared)) { _ in
            quoteStore.clearCache()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let cloudSync: Void = cloud.run()
            async let quotePolling: Void = quoteStore.start { self.marketBasis }
            _ = await (cloudSync, quotePolling)
        }
        .modifier(HoldingAlertsLifecycle())
    }
}
