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
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HoldingWorkspaceShell(session: session, guestContainer: guestContainer)
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
    @State private var cloud: HoldingsCloud?
    @State private var storageError: String?
    var body: some View {
        Group {
            if let cloud {
                GoldWorkspaceView(session: session, cloud: cloud)
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
    @State private var selectedTab = HoldingsDesignPreview.isEnabled ? 1 : 0
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("market.basis") private var marketBasisRaw = GoldMarketBasis.domestic.rawValue
    @State private var showingAdd = false
    @State private var showingNotice = false

    private var marketBasis: GoldMarketBasis {
        GoldMarketBasis(rawValue: marketBasisRaw) ?? .domestic
    }

    private var marketBasisBinding: Binding<GoldMarketBasis> {
        Binding(
            get: { GoldMarketBasis(rawValue: marketBasisRaw) ?? .domestic },
            set: { marketBasisRaw = $0.rawValue }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 430
            ZStack(alignment: .bottom) {
                GoldTheme.background.ignoresSafeArea()
                if selectedTab == 0 {
                    HomeView(marketBasis: marketBasisBinding)
                } else if selectedTab == 3 {
                    AccountView(session: session, cloud: cloud)
                        .padding(.bottom, 80 * scale)
                } else {
                    HoldingsView(marketBasis: marketBasis, cloud: cloud)
                        .id(marketBasis.rawValue)
                        .padding(.bottom, 80 * scale)
                }
                tabBar(scale: scale)
                    .frame(height: 80 * scale)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(defaultUnitPrice: nil, marketBasis: marketBasis)
        }
        .alert("功能尚未接入", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("记账功能暂未开放。")
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await cloud.run() }
        }
        .modifier(HoldingAlertsLifecycle())
        .persistentSystemOverlays(.hidden)
    }

    private func tabBar(scale: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                GoldTabBarShape().fill(GoldTheme.card)
                tabItem("动态", symbol: "house.fill", index: 0, scale: scale)
                    .position(x: width * 0.1, y: 42 * scale)
                tabItem("记金", symbol: "bag.fill", index: 1, scale: scale)
                    .position(x: width * 0.3, y: 42 * scale)
                tabItem("记账", symbol: "yensign.square.fill", index: 2, scale: scale)
                    .position(x: width * 0.7, y: 42 * scale)
                tabItem("我的", symbol: "person.fill", index: 3, scale: scale)
                    .position(x: width * 0.9, y: 42 * scale)
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 32 * scale, weight: .semibold))
                        .foregroundStyle(GoldTheme.card)
                        .frame(width: 65 * scale, height: 65 * scale)
                        .background(GoldTheme.gold, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加黄金")
                .position(x: width / 2, y: 16 * scale)
            }
        }
    }

    private func tabItem(_ title: String, symbol: String, index: Int, scale: CGFloat) -> some View {
        Button {
            if index < 2 || index == 3 { selectedTab = index } else { showingNotice = true }
        } label: {
            VStack(spacing: 7 * scale) {
                if index == 1 {
                    GoldMoneyBagShape()
                        .fill(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
                        .frame(width: 25 * scale, height: 25 * scale)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 23 * scale, weight: .semibold))
                        .frame(height: 25 * scale)
                }
                Text(title)
                    .font(.system(size: 11 * scale))
            }
            .foregroundStyle(selectedTab == index ? GoldTheme.gold : GoldTheme.textSecondary)
            .frame(width: 64 * scale, height: 58 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }
}
