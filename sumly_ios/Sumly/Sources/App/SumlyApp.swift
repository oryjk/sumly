import SwiftUI
import SwiftData
import AuthenticationServices

@main
struct SumlyApp: App {
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

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
            if Self.isRunningUnitTests {
                Color.clear
            } else {
                GoldRootView(guestContainer: Self.holdingsContainer)
                    .tint(GoldTheme.gold)
                    .preferredColorScheme(.dark)
                    .modelContainer(Self.holdingsContainer)
            }
        }
    }
}


private struct GoldRootView: View {
    let guestContainer: ModelContainer
    @State private var session = AuthSession(service: NativeAuthService(baseURL: BackendGoldPriceService.defaultBaseURL), store: KeychainCredentialStore())
    @State private var membership = MembershipStore()
    @State private var remoteConfig = RemoteAppConfigStore()
    @State private var languageStore = AppLanguageStore.shared
    @State private var selectedTab = HoldingsDesignPreview.isEnabled ? 1 : 0
    @State private var pendingChanlunAfterLogin = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HoldingWorkspaceShell(
            session: session,
            membership: membership,
            remoteConfig: remoteConfig,
            guestContainer: guestContainer,
            selectedTab: $selectedTab,
            pendingChanlunAfterLogin: $pendingChanlunAfterLogin
        )
            .id(session.user?.id ?? 0)
            .environment(languageStore)
            .environment(\.locale, languageStore.effectiveLocale)
            .task {
                async let restoreSession: Void = session.restore()
                async let startMembership: Void = membership.start()
                async let refreshRemoteConfig: Bool = remoteConfig.refresh()
                _ = await (restoreSession, startMembership, refreshRemoteConfig)
                await session.checkAppleCredential(using: SystemAppleCredentialChecker())
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task {
                    async let restoreSession: Void = session.restore()
                    async let refreshMembership: Void = membership.refresh()
                    async let refreshRemoteConfig: Bool = remoteConfig.refresh()
                    _ = await (restoreSession, refreshMembership, refreshRemoteConfig)
                    await session.checkAppleCredential(using: SystemAppleCredentialChecker())
                } }
            }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                if session.stored?.appleUserID != nil {
                    session.clearLocal()
                    session.notice = L10n.tr("Apple 授权已撤销，请重新登录。")
                }
            }
    }
}

private struct HoldingWorkspaceShell: View {
    let session: AuthSession
    let membership: MembershipStore
    let remoteConfig: RemoteAppConfigStore
    let guestContainer: ModelContainer
    @Binding var selectedTab: Int
    @Binding var pendingChanlunAfterLogin: Bool
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var cloud: HoldingsCloud?
    @State private var storageError: String?
    var body: some View {
        let _ = languageStore.revision
        Group {
            if let cloud {
                GoldWorkspaceView(
                    session: session,
                    membership: membership,
                    remoteConfig: remoteConfig,
                    cloud: cloud,
                    selectedTab: $selectedTab,
                    pendingChanlunAfterLogin: $pendingChanlunAfterLogin
                )
                    .modelContainer(cloud.container)
                    .defaultAppStorage(cloud.defaults)
            } else if let storageError {
                VStack(spacing: 16) {
                    Text(L10n.tr("无法打开持仓缓存")).font(.headline)
                    Text(storageError).font(.footnote)
                    Button(L10n.tr("重试")) { openWorkspace() }
                }.padding().foregroundStyle(GoldTheme.text)
            } else { ProgressView(L10n.tr("正在打开持仓…")) }
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
    @Bindable var membership: MembershipStore
    @Bindable var remoteConfig: RemoteAppConfigStore
    let cloud: HoldingsCloud
    @Binding var selectedTab: Int
    @Binding var pendingChanlunAfterLogin: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppLanguageStore.self) private var languageStore
    @AppStorage private var marketBasisRaw: String
    @AppStorage("market.showHoldingOverlay") private var showHoldingOverlay = true
    @AppStorage("holdings.currentBook") private var currentBook = "默认账本"
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @AppStorage(OnboardingStorageKey.completedVersion, store: .standard) private var onboardingCompletedVersion = 0
    @AppStorage(OnboardingStorageKey.quickStartDismissed, store: .standard) private var quickStartDismissed = false
    @AppStorage(OnboardingStorageKey.visitedChartOverlay, store: .standard) private var visitedChartOverlay = false
    @AppStorage(OnboardingStorageKey.visitedCalendar, store: .standard) private var visitedCalendar = false
    @State private var quoteStore = LiveGoldQuoteStore()
    @State private var showingAdd = false
    @State private var showingOnboarding = false
    @State private var pendingAddAfterOnboarding = false
    @State private var hasEvaluatedOnboardingLaunch = false
    @State private var showingChartOverlayHint = false
    @State private var chartOverlayHintTask: Task<Void, Never>?
    @State private var showingMembershipPaywall = false
    @State private var pendingChanlunAfterPaywall = false
    @State private var showingLoginForChanlun = false
    @State private var showingChanlun = false

    init(
        session: AuthSession,
        membership: MembershipStore,
        remoteConfig: RemoteAppConfigStore,
        cloud: HoldingsCloud,
        selectedTab: Binding<Int>,
        pendingChanlunAfterLogin: Binding<Bool>
    ) {
        self.session = session
        self.membership = membership
        self.remoteConfig = remoteConfig
        self.cloud = cloud
        self._selectedTab = selectedTab
        self._pendingChanlunAfterLogin = pendingChanlunAfterLogin
        let initialBasis = GoldMarketBasis.resolveInitialBasis(in: cloud.defaults)
        self._marketBasisRaw = AppStorage(
            wrappedValue: initialBasis.rawValue,
            GoldMarketBasis.storageKey,
            store: cloud.defaults
        )
    }

    private var marketBasis: GoldMarketBasis {
        GoldMarketBasis(rawValue: marketBasisRaw) ?? GoldMarketBasis.initialDefault()
    }

    private var marketBasisBinding: Binding<GoldMarketBasis> {
        Binding(
            get: { GoldMarketBasis(rawValue: marketBasisRaw) ?? GoldMarketBasis.initialDefault() },
            set: { marketBasisRaw = $0.rawValue }
        )
    }

    private var canAccessChanlun: Bool {
        !remoteConfig.chanlunRequiresMembership || membership.isActive
    }

    private func openChanlun() {
        switch MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: ChanlunWebConfiguration.current != nil,
            isMemberActive: membership.isActive,
            isSignedIn: session.user != nil,
            requiresMembership: remoteConfig.chanlunRequiresMembership
        ) {
        case .unavailable:
            break
        case .openPaywall:
            pendingChanlunAfterPaywall = true
            showingMembershipPaywall = true
        case .openLogin:
            pendingChanlunAfterLogin = true
            showingLoginForChanlun = true
        case .openChanlun:
            showingChanlun = true
        }
    }

    private func openMembership() {
        pendingChanlunAfterPaywall = false
        showingMembershipPaywall = true
    }

    private func openOnboarding() {
        showingOnboarding = true
    }

    private func evaluateOnboardingLaunch() {
        guard !hasEvaluatedOnboardingLaunch,
              !HoldingsDesignPreview.isEnabled,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        hasEvaluatedOnboardingLaunch = true
        let workspaceCount = (try? cloud.container.mainContext.fetchCount(FetchDescriptor<HoldingRecord>())) ?? 0
        let existingCount = max(workspaceCount, cloud.guestRecordCount)
        switch OnboardingGate.evaluateLaunch(
            completedVersion: onboardingCompletedVersion,
            existingHoldingCount: existingCount
        ) {
        case .present:
            showingOnboarding = true
        case .markCompletedSilently:
            onboardingCompletedVersion = OnboardingGate.currentVersion
        case .skip:
            break
        }
    }

    private func openChartOverlayGuide() {
        visitedChartOverlay = true
        showHoldingOverlay = true
        selectedTab = 0
        chartOverlayHintTask?.cancel()
        withAnimation(.easeOut(duration: 0.22)) {
            showingChartOverlayHint = true
        }
        chartOverlayHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showingChartOverlayHint = false
            }
        }
    }

    private func dismissChartOverlayHint() {
        chartOverlayHintTask?.cancel()
        chartOverlayHintTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            showingChartOverlayHint = false
        }
    }

    var body: some View {
        let languageRevision = languageStore.revision
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
                        isMembershipActive: membership.isActive,
                        chanlunRequiresMembership: remoteConfig.chanlunRequiresMembership,
                        onOpenHoldings: { selectedTab = 1 },
                        onOpenChanlun: openChanlun
                    )
                    .id(languageRevision)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
                    .accessibilityHidden(selectedTab != 0)

                    HoldingsView(
                        marketBasis: marketBasis,
                        cloud: cloud,
                        quoteStore: quoteStore,
                        onOpenCalendar: {
                            visitedCalendar = true
                            selectedTab = 2
                        },
                        onOpenChartOverlay: openChartOverlayGuide
                    )
                    .id(languageRevision)
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
                    .id(languageRevision)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
                    .accessibilityHidden(selectedTab != 2)

                    AccountView(
                        session: session,
                        cloud: cloud,
                        membership: membership,
                        remoteConfig: remoteConfig,
                        onOpenMembership: openMembership,
                        onOpenChanlun: openChanlun,
                        onOpenOnboarding: openOnboarding
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

                if selectedTab == 0 && showingChartOverlayHint {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GoldTheme.gold)
                            Text(L10n.tr("已开启「持仓」叠加 · 切至近 1 月及以上可看保本线与买入红点"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(GoldTheme.text)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button {
                                dismissChartOverlayHint()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(GoldTheme.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr("关闭提示"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(GoldTheme.card.opacity(0.96), in: GoldTheme.subCardShape)
                        .overlay(
                            GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
                        )
                        .shadow(color: GoldTheme.tabBarShadow, radius: 10, x: 0, y: 4)
                        .padding(.horizontal, 18)
                        .padding(.top, 58)
                        Spacer(minLength: 0)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onChange(of: selectedTab) { _, tab in
            if tab == 2 {
                visitedCalendar = true
            }
            if tab != 0 && showingChartOverlayHint {
                dismissChartOverlayHint()
            }
        }
        .onChange(of: showHoldingOverlay) { _, _ in
            visitedChartOverlay = true
        }
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(
                defaultUnitPrice: quoteStore.quote(for: marketBasis)?.cnyPerGram,
                marketBasis: marketBasis
            )
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: {
            if onboardingCompletedVersion < OnboardingGate.currentVersion {
                onboardingCompletedVersion = OnboardingGate.currentVersion
            }
            if pendingAddAfterOnboarding {
                pendingAddAfterOnboarding = false
                showingAdd = true
            }
        }) {
            OnboardingSheetView(
                onCompleteAndRecord: {
                    onboardingCompletedVersion = OnboardingGate.currentVersion
                    pendingAddAfterOnboarding = true
                    showingOnboarding = false
                },
                onDismiss: {
                    onboardingCompletedVersion = OnboardingGate.currentVersion
                    showingOnboarding = false
                }
            )
            .presentationBackground(GoldTheme.background)
        }
        .sheet(isPresented: $showingMembershipPaywall, onDismiss: {
            if pendingChanlunAfterPaywall {
                pendingChanlunAfterPaywall = false
                if canAccessChanlun {
                    openChanlun()
                }
            }
        }) {
            MembershipPaywallSheet(
                membership: membership,
                autoDismissOnUnlock: pendingChanlunAfterPaywall,
                onOpenChanlun: ChanlunWebConfiguration.current != nil ? {
                    pendingChanlunAfterPaywall = true
                    showingMembershipPaywall = false
                } : nil
            )
        }
        .sheet(isPresented: $showingLoginForChanlun, onDismiss: {
            if session.user == nil {
                pendingChanlunAfterLogin = false
            } else if pendingChanlunAfterLogin && canAccessChanlun {
                pendingChanlunAfterLogin = false
                showingChanlun = true
            }
        }) {
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
        .task(id: cloud.id) {
            evaluateOnboardingLaunch()
            if pendingChanlunAfterLogin,
               session.user != nil,
               canAccessChanlun,
               ChanlunWebConfiguration.current != nil {
                pendingChanlunAfterLogin = false
                showingChanlun = true
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let cloudSync: Void = cloud.run()
            async let quotePolling: Void = quoteStore.start { self.marketBasis }
            _ = await (cloudSync, quotePolling)
        }
        .onDisappear {
            chartOverlayHintTask?.cancel()
            chartOverlayHintTask = nil
        }
        .modifier(HoldingAlertsLifecycle())
    }
}
