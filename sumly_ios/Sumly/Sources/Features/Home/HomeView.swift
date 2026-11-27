import SwiftUI
import SwiftData
import Charts

/// 参考稿高保真布局，行情统一由 Go 服务提供。
struct HomeView: View {
    @Binding private var marketBasis: GoldMarketBasis
    private let quoteStore: LiveGoldQuoteStore?
    private let macroService: any MacroServicing
    private let bottomTabBarInset: CGFloat?
    private let isMembershipActive: Bool
    private let chanlunRequiresMembership: Bool
    private let onOpenHoldings: (() -> Void)?
    private let onOpenChanlun: (() -> Void)?
    @Query private var records: [HoldingRecord]
    @AppStorage("holdings.currentBook") private var currentBook = Self.defaultBookStorageName
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @AppStorage("market.showHoldingOverlay") private var showHoldingOverlay = true
    @State private var model: MarketHomeViewModel
    @State private var macroModel: MacroDashboardViewModel
    @State private var showingMacroDashboard = false
    @State private var macroLoadTrigger = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHistorySources = false
    @State private var showingDates = false
    @State private var selectedPurchaseMarker: ChartHoldingMarkerResolver.ResolvedMarker?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var basisHighlight
    @State private var highlightedBasis: GoldMarketBasis
    @State private var pendingBasis: GoldMarketBasis?
    @State private var outgoing: MarketHomeViewModel?
    @State private var crossfadeProgress = 1.0
    @State private var basisSwitchTask: Task<Void, Never>?
    @State private var showingBasisError = false
    @State private var transitionID: UUID?

    init(
        marketBasis: Binding<GoldMarketBasis>,
        quoteStore: LiveGoldQuoteStore? = nil,
        macroService: any MacroServicing = BackendMacroService(),
        bottomTabBarInset: CGFloat? = nil,
        isMembershipActive: Bool = false,
        chanlunRequiresMembership: Bool = true,
        onOpenHoldings: (() -> Void)? = nil,
        onOpenChanlun: (() -> Void)? = nil
    ) {
        _highlightedBasis = State(initialValue: marketBasis.wrappedValue)
        _marketBasis = marketBasis
        self.quoteStore = quoteStore
        self.macroService = macroService
        self.bottomTabBarInset = bottomTabBarInset
        self.isMembershipActive = isMembershipActive
        self.chanlunRequiresMembership = chanlunRequiresMembership
        self.onOpenHoldings = onOpenHoldings
        self.onOpenChanlun = onOpenChanlun
        _model = State(initialValue: MarketHomeViewModel(basis: marketBasis.wrappedValue))
        _macroModel = State(initialValue: MacroDashboardViewModel(service: macroService))
    }

    private var showsChanlunLockBadge: Bool {
        MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: chanlunRequiresMembership,
            isMemberActive: isMembershipActive
        )
    }

    private static let defaultBookStorageName = "默认账本"

    private var displayedBookName: String {
        currentBook == Self.defaultBookStorageName ? L10n.tr("默认账本") : currentBook
    }

    private var activeBookRecords: [HoldingRecord] {
        records.filter { $0.bookName == currentBook && $0.disposition == "holding" }
    }

    private var holdingOverlay: MarketHoldingOverlay? {
        guard !activeBookRecords.isEmpty else { return nil }
        return HoldingsInsights.marketOverlay(
            entries: activeBookRecords.map(\.insightEntry),
            window: nil,
            referencePrice: model.price
        )
    }

    private var currentQuoteSnapshot: MarketQuoteSnapshot? {
        model.quote.flatMap { MarketQuoteSnapshot.make(from: $0, basis: model.basis) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.showsInitialLoading {
                    MarketLoadingView()
                } else {
                    dashboard
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingMacroDashboard) {
                MacroDashboardView(model: macroModel, service: macroService)
            }
        }
        .tint(GoldTheme.gold)
        .onReceive(NotificationCenter.default.publisher(for: .marketCacheCleared)) { _ in
            stopBasisTransition()
            model.clearMarketCache()
        }
        .onDisappear { stopBasisTransition(); model.selectedDate = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopBasisTransition(); model.selectedDate = nil }
        }
        .alert(L10n.tr("口径切换失败"), isPresented: $showingBasisError) {
            Button(L10n.tr("知道了"), role: .cancel) {}
        } message: {
            Text(L10n.tr("已保留原口径数据，请检查网络后重试。"))
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.start() }
        }
        .task(id: MacroSummaryLoadKey(scenePhase: scenePhase, trigger: macroLoadTrigger)) {
            guard scenePhase == .active else { return }
            await macroModel.loadSummary()
        }
        .onChange(of: showingMacroDashboard) { _, isPresented in
            if !isPresented { ensureMacroSummaryLoaded() }
        }
        .onChange(of: model.showsInitialLoading) { _, isLoading in
            if !isLoading { ensureMacroSummaryLoaded() }
        }
        .task(id: model.range) {
            if model.range != .realtime { await model.loadHistory() }
        }
        .onChange(of: model.quote) { _, latest in
            if let latest { quoteStore?.ingest(latest, for: model.basis) }
        }
        .sensoryFeedback(.selection, trigger: highlightedBasis)
        .sheet(isPresented: $showingDates) {
            ChartDateRangeSheet(bounds: model.fullDomain, window: model.xDomain, apply: model.setDateWindow)
        }
        .sheet(item: $selectedPurchaseMarker) { resolved in
            ChartPurchaseMarkerSheet(
                resolvedMarker: resolved,
                marketBasis: model.basis,
                hideAmounts: hideAmounts,
                currentQuote: model.quote ?? quoteStore?.quote(for: model.basis),
                recordLookup: { id in
                    activeBookRecords.first(where: { $0.id == id }) ?? records.first(where: { $0.id == id })
                }
            )
        }
        .sheet(isPresented: $showingHistorySources) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.tr("实时走势如何比较")).font(.headline)
                        Text(L10n.tr("国内为 Au99.99 人民币/克报价；国际为伦敦金按汇率折算的人民币/克参考价，两者分别来自各自市场。"))
                        Text(L10n.tr("实时页展示当日完整分时走势（国内连贯展示当日日盘 09:00–15:30 与夜盘 20:00–次日 02:30，国际展示完整 23 小时交易日），并以昨收虚线区分红涨绿跌。休市或非交易时段保留收盘前真实走势与时间，不补造价格。"))
                        if model.basis == .domestic {
                            Text(L10n.tr("国内 · Au99.99")).font(.headline)
                            Text(L10n.tr("实时价格来自新浪 Au99.99 报价，历史日线来自上海黄金交易所。价格原始单位就是人民币/克，不做美元汇率换算。"))
                            Text(L10n.tr("走势图只展示真实可用交易数据；周末、休市及缺失日期不补造价格。"))
                        } else {
                            Text(L10n.tr("1900–2015 · 年度均价参考")).font(.headline)
                            Text(L10n.tr("来源为 USGS Data Series 140 的名义美元金价统计，按每吨换算为每金衡盎司。1900–1967 年依据世界市场均价，1968 年起依据 Engelhard 年均报价；不是同一市场的逐日收盘序列。年度点仅用当年 7 月定位。"))
                            Link(L10n.tr("查看 USGS 原始资料"), destination: URL(string: "https://www.usgs.gov/media/files/gold-historical-statistics-data-series-140")!)
                            Text(L10n.tr("2016 年起 · 每日收盘价")).font(.headline)
                            Text(L10n.tr("来源为新浪伦敦金日线，仅展示截至昨天已有的交易日收盘数据。当天报价仅在实时走势中显示。周末、休市及缺失数据不补点。"))
                            Text(L10n.tr("图中元/克按最新美元兑人民币汇率折算，不代表当年的人民币价格，也未作通胀调整。"))
                        }
                    }.padding(24)
                }.background(GoldTheme.background).foregroundStyle(GoldTheme.text)
                    .navigationTitle(L10n.tr("行情数据说明"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { showingHistorySources = false } } }
            }.preferredColorScheme(.dark).tint(GoldTheme.gold)
        }
    }

    private var dashboard: some View {
        GeometryReader { geometry in
            let bottomInset = bottomTabBarInset ?? GoldTabBarLayout.resolve(
                containerWidth: geometry.size.width,
                safeAreaBottom: geometry.safeAreaInsets.bottom
            ).homeAdditionalBottomInset
            let availableChartContentHeight = max(0, geometry.size.height - bottomInset - 66)
            ScrollView {
                VStack(spacing: 14) {
                    ZStack {
                        HStack {
                            Button {
                                showingMacroDashboard = true
                            } label: {
                                let hasScore = macroModel.temperature?.hasAvailableData == true
                                let pillTint = hasScore
                                    ? MacroPresentation.temperatureColor(for: macroModel.temperature?.level ?? .neutral)
                                    : GoldTheme.goldSoft
                                HStack(spacing: 4) {
                                    Image(systemName: "thermometer.medium")
                                        .font(.caption.weight(.semibold))
                                    Text(hasScore ? String(format: "%.0f°", macroModel.temperature?.clampedScore ?? 0) : L10n.tr("温度"))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(pillTint)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr("查看黄金温度与美国国债"))
                            .accessibilityIdentifier("home.macroEntryButton")
                            Spacer()
                        }

                        marketBasisPicker

                        if ChanlunWebConfiguration.current != nil, let onOpenChanlun {
                            HStack {
                                Spacer()
                                Button(action: onOpenChanlun) {
                                    HStack(spacing: 3.5) {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .font(.caption.weight(.semibold))
                                        Text(L10n.tr("禅观"))
                                            .font(.caption.weight(.semibold))
                                        if showsChanlunLockBadge {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 8.5, weight: .bold))
                                                .foregroundStyle(GoldTheme.gold)
                                        }
                                    }
                                    .foregroundStyle(GoldTheme.goldSoft)
                                    .padding(.horizontal, showsChanlunLockBadge ? 8.5 : 10)
                                    .frame(height: 34)
                                    .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                                    .overlay(
                                        GoldTheme.capsuleShape.strokeBorder(
                                            showsChanlunLockBadge ? GoldTheme.gold.opacity(0.32) : GoldTheme.cardStroke,
                                            lineWidth: 1
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showsChanlunLockBadge ? L10n.tr("禅观，记金会员专属") : L10n.tr("禅观"))
                                .accessibilityIdentifier("companion.chanlun")
                            }
                        }
                    }
                    .padding(.top, 8)

                    MarketHomeChartContent(
                        model: model,
                        availableHeight: availableChartContentHeight,
                        showingHistorySources: $showingHistorySources,
                        showingDates: $showingDates,
                        holdingOverlay: holdingOverlay,
                        showHoldingOverlay: showHoldingOverlay,
                        hideAmounts: hideAmounts,
                        highlightedMarkerID: selectedPurchaseMarker?.id,
                        onToggleHoldingOverlay: {
                            withAnimation(.easeInOut(duration: 0.18)) { showHoldingOverlay.toggle() }
                        },
                        onSelectPurchaseMarker: { resolved in
                            model.selectedDate = nil
                            selectedPurchaseMarker = resolved
                        }
                    )
                        .transaction { $0.animation = nil }
                        .opacity(crossfadeProgress)
                        .overlay(alignment: .top) {
                            if let outgoing {
                                MarketHomeChartContent(model: outgoing, availableHeight: availableChartContentHeight,
                                    showingHistorySources: $showingHistorySources, showingDates: $showingDates)
                                    .transaction { $0.animation = nil }
                                    .opacity(1 - crossfadeProgress)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                    .onAppear { beginCrossfade() }
                            }
                        }
                        .allowsHitTesting(outgoing == nil)

                    GoldTemperatureCard(
                        temperature: macroModel.temperature,
                        treasury: macroModel.treasury?.summary,
                        isLoading: macroModel.isSummaryLoading,
                        errorMessage: macroModel.temperatureError,
                        onRetry: { Task { await macroModel.loadSummary(force: true) } },
                        onOpenDashboard: { showingMacroDashboard = true }
                    )
                    .padding(.top, 14)

                    if let snapshot = currentQuoteSnapshot {
                        marketMetricsCard(snapshot: snapshot)
                    }

                    if !activeBookRecords.isEmpty {
                        holdingsLinkCard
                    }
                }.padding(.horizontal, 18).padding(.bottom, bottomInset)
            }.scrollIndicators(.hidden).background(GoldTheme.background)
        }
    }

    private func marketMetricsCard(snapshot: MarketQuoteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("今日盘口参考"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                Text(L10n.fmt("%@ · 元/克", snapshot.basis.title))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCell(L10n.tr("今开"), snapshot.openCNY.map { "¥" + $0.moneyText } ?? "—")
                metricCell(L10n.tr("昨收"), snapshot.prevCloseCNY.map { "¥" + $0.moneyText } ?? "—")
                metricCell(L10n.tr("最高"), snapshot.highCNY.map { "¥" + $0.moneyText } ?? "—", tint: GoldTheme.up)
                metricCell(L10n.tr("最低"), snapshot.lowCNY.map { "¥" + $0.moneyText } ?? "—", tint: GoldTheme.down)
            }
            if let spread = quoteStore?.spread {
                GoldTheme.cardStroke.frame(height: 1)
                HStack(spacing: 8) {
                    Text(L10n.tr("沪伦实时价差"))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer()
                    let label = spread.spreadCNY >= 0 ? L10n.tr("国内溢价") : L10n.tr("国内折价")
                    Text(L10n.fmt("%@ %@ 元/克 (%@%%)", label, spread.spreadCNY.signedMoneyText, spread.spreadPercent.signedMoneyText))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(spread.spreadCNY >= 0 ? GoldTheme.up : GoldTheme.down)
                }
            }
            if let usd = snapshot.usdPerOz, let fx = snapshot.usdCNY {
                HStack(spacing: 8) {
                    Text(L10n.tr("伦敦金现货"))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer()
                    Text(L10n.fmt("$%@/oz · 汇率 %@", usd.moneyText, fx.formatted(.number.precision(.fractionLength(2...4)))))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
        }
        .goldCard(padding: 16)
    }

    private func metricCell(_ title: String, _ value: String, tint: Color = GoldTheme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
            Text(value)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var holdingsLinkCard: some View {
        let portfolio = GoldReturnCalculator.aggregate(activeBookRecords.map(\.returnInput), referencePrice: model.price)
        return Button {
            onOpenHoldings?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.fmt("我的持仓 · %@", displayedBookName), systemImage: "bag.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(GoldTheme.gold)
                    Spacer()
                    Text(hideAmounts ? "•••• g" : "\((portfolio?.grams ?? 0).moneyText) g")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("预计到手"))
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text(GoldReturnPresentation.money(portfolio?.proceeds, hidden: hideAmounts))
                            .font(.system(.title3, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.tr("真实盈亏"))
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text(GoldReturnPresentation.money(portfolio?.profit, hidden: hideAmounts, signed: true))
                            .font(.system(.title3, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(hideAmounts ? GoldTheme.text : (portfolio?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    }
                }
                Text(GoldReturnPresentation.status(price: model.price, breakEven: portfolio?.breakEvenPrice, hidden: hideAmounts))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.goldSoft)
            }
            .goldCard(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var marketBasisPicker: some View {
        HStack(spacing: 4) {
            ForEach(GoldMarketBasis.allCases) { basis in
                Button { switchBasis(to: basis) } label: {
                    Text(basis.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(highlightedBasis == basis ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if highlightedBasis == basis {
                                if reduceMotion {
                                    GoldTheme.capsuleShape.fill(GoldTheme.gold)
                                } else {
                                    GoldTheme.capsuleShape.fill(GoldTheme.gold)
                                        .matchedGeometryEffect(id: "basisHighlight", in: basisHighlight)
                                }
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if pendingBasis == basis && outgoing == nil {
                                ProgressView().controlSize(.mini).tint(GoldTheme.goldSoft)
                                    .padding(.trailing, 6)
                            }
                        }
                }
                .buttonStyle(BasisPressStyle())
                .disabled(pendingBasis != nil)
                .accessibilityLabel(L10n.fmt("黄金口径，%@", basis.title))
                .accessibilityAddTraits(model.basis == basis ? .isSelected : [])
                .accessibilityValue(pendingBasis == basis ? L10n.tr("正在切换") : (model.basis == basis ? L10n.tr("已选中") : ""))
                .accessibilityIdentifier("market.basis.\(basis.rawValue)")
            }
        }
        .padding(4)
        .frame(width: 190)
        .background(GoldTheme.card, in: GoldTheme.capsuleShape)

    }

    private func switchBasis(to basis: GoldMarketBasis) {
        guard pendingBasis == nil, basis != model.basis else { return }
        selectedPurchaseMarker = nil
        pendingBasis = basis
        transitionID = UUID()
        basisSwitchTask = Task { @MainActor in
            let success = await model.switchBasis(to: basis, beforeCommit: {
                // Capture immediately before the atomic commit, so slow requests
                // never fade the current view out while the next basis is loading.
                outgoing = model.makeDisplaySnapshot()
                crossfadeProgress = 0
            })
            guard !Task.isCancelled else { return }
            guard success else {
                pendingBasis = nil; basisSwitchTask = nil; transitionID = nil
                showingBasisError = true
                return
            }
            marketBasis = basis
            basisSwitchTask = nil
            // The outgoing layer starts the fade on appearance, after SwiftUI
            // has installed the initial old=1/new=0 presentation values.
        }
    }

    private func beginCrossfade() {
        guard let id = transitionID, outgoing != nil, crossfadeProgress == 0 else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.25), completionCriteria: .removed) {
            crossfadeProgress = 1
            highlightedBasis = model.basis
        } completion: {
            guard transitionID == id else { return }
            outgoing = nil
            pendingBasis = nil
            transitionID = nil
        }
    }

    private func ensureMacroSummaryLoaded() {
        guard scenePhase == .active, !showingMacroDashboard else { return }
        guard !macroModel.isLoadingTemperature, !macroModel.isLoadingTreasury else { return }
        let needsTemperature = macroModel.temperature == nil && macroModel.temperatureError == nil
        let needsTreasury = macroModel.treasury == nil && macroModel.treasuryError == nil
        if needsTemperature || needsTreasury {
            macroLoadTrigger &+= 1
        }
    }

    private func stopBasisTransition() {
        basisSwitchTask?.cancel()
        model.cancelBasisSwitch()
        basisSwitchTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionID = nil
            outgoing = nil
            crossfadeProgress = 1
            pendingBasis = nil
            highlightedBasis = model.basis
        }
    }
}

private struct MacroSummaryLoadKey: Equatable {
    let scenePhase: ScenePhase
    let trigger: Int
}

private struct BasisPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
