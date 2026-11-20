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
            let safeBottom = geometry.safeAreaInsets.bottom
            let barBodyHeight: CGFloat = 64
            let totalBarHeight = barBodyHeight + safeBottom
            ZStack(alignment: .bottom) {
                GoldTheme.background.ignoresSafeArea()

                // Keep all 4 primary tabs alive so switching tabs preserves scroll, navigation stacks, and chart state.
                ZStack {
                    HomeView(
                        marketBasis: marketBasisBinding,
                        quoteStore: quoteStore,
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
                    .padding(.bottom, totalBarHeight)
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
                    .padding(.bottom, totalBarHeight)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
                    .accessibilityHidden(selectedTab != 2)

                    AccountView(
                        session: session,
                        cloud: cloud,
                        onOpenChanlun: openChanlun
                    )
                    .padding(.bottom, totalBarHeight)
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
                    .accessibilityHidden(selectedTab != 3)
                }

                tabBar(barBodyHeight: barBodyHeight, safeBottom: safeBottom)
                    .frame(height: totalBarHeight)
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

    private func tabBar(barBodyHeight: CGFloat, safeBottom: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let addDiameter: CGFloat = 56
            ZStack(alignment: .topLeading) {
                GoldTabBarShape()
                    .fill(GoldTheme.card)
                    .overlay(alignment: .top) {
                        GoldTabBarShape()
                            .stroke(GoldTheme.cardStroke, lineWidth: 0.75)
                    }
                tabItem("行情", symbol: "chart.xyaxis.line", index: 0)
                    .position(x: width * 0.1, y: barBodyHeight * 0.54)
                tabItem("持仓", symbol: "bag.fill", index: 1)
                    .position(x: width * 0.3, y: barBodyHeight * 0.54)
                tabItem("日历", symbol: "calendar", index: 2)
                    .position(x: width * 0.7, y: barBodyHeight * 0.54)
                tabItem("我的", symbol: "person.fill", index: 3)
                    .position(x: width * 0.9, y: barBodyHeight * 0.54)
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(GoldTheme.onGold)
                        .frame(width: addDiameter, height: addDiameter)
                        .background(GoldTheme.gold, in: Circle())
                        .shadow(color: GoldTheme.gold.opacity(0.28), radius: 8, y: 3)
                }
                .buttonStyle(GoldScalePressStyle())
                .accessibilityLabel("添加黄金")
                .position(x: width / 2, y: 18)
            }
            .padding(.bottom, safeBottom > 0 ? 0 : 2)
        }
    }

    private func tabItem(_ title: String, symbol: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 5) {
                if index == 1 {
                    GoldMoneyBagShape()
                        .fill(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 22)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: selectedTab == index ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
            .frame(width: 64, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(GoldScalePressStyle())
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }
}

private struct GoldScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
