import SwiftUI
import SwiftData

struct HoldingsCalendarSheet: View {
    let initialBook: String
    let hideAmounts: Bool
    let marketBasis: GoldMarketBasis
    let quoteStore: LiveGoldQuoteStore?
    let isEmbeddedTab: Bool

    @Query private var records: [HoldingRecord]
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter = HoldingCalendarFilter()
    @State private var didInitialize = false
    @State private var showingFilter = false
    @State private var showingAdd = false
    @State private var showingPoster = false
    @State private var showingYearMonthPicker = false
    @State private var statsPeriod: CalendarStatsScope = .month
    @State private var sectionExpansion: [CalendarStatisticsKind: Bool] = [:]
    @State private var model: HoldingsViewModel
    @State private var calendarVM: HoldingsCalendarViewModel
    private let skipAutomaticNetworkSync: Bool

    init(
        initialBook: String,
        hideAmounts: Bool,
        marketBasis: GoldMarketBasis = .domestic,
        quoteStore: LiveGoldQuoteStore? = nil,
        isEmbeddedTab: Bool = false
    ) {
        self.initialBook = initialBook
        self.hideAmounts = hideAmounts
        self.marketBasis = marketBasis
        self.quoteStore = quoteStore
        self.isEmbeddedTab = isEmbeddedTab
        self.skipAutomaticNetworkSync = false
        let vm = HoldingsDesignPreview.makeModel(basis: marketBasis)
        if let quoteStore {
            vm.applyExternalQuote(quoteStore.quote(for: marketBasis), failed: quoteStore.isFailed(for: marketBasis))
        }
        _model = State(initialValue: vm)
        _calendarVM = State(initialValue: HoldingsCalendarViewModel())
    }

    /// 供单测与模拟器可视化渲染注入预置视图模型，避免外部网络干扰。
    init(
        initialBook: String,
        hideAmounts: Bool,
        marketBasis: GoldMarketBasis = .domestic,
        quoteStore: LiveGoldQuoteStore? = nil,
        isEmbeddedTab: Bool = false,
        preloadedViewModel: HoldingsCalendarViewModel
    ) {
        self.initialBook = initialBook
        self.hideAmounts = hideAmounts
        self.marketBasis = marketBasis
        self.quoteStore = quoteStore
        self.isEmbeddedTab = isEmbeddedTab
        self.skipAutomaticNetworkSync = true
        let vm = HoldingsDesignPreview.makeModel(basis: marketBasis)
        if let quoteStore {
            vm.applyExternalQuote(quoteStore.quote(for: marketBasis), failed: quoteStore.isFailed(for: marketBasis))
        }
        _model = State(initialValue: vm)
        _calendarVM = State(initialValue: preloadedViewModel)
    }

    private var activeQuote: GoldQuote? {
        quoteStore?.quote(for: marketBasis) ?? model.quote
    }

    private var books: [String] {
        Array(Set(records.map(\.bookName) + savedBooks.components(separatedBy: "\n") + [initialBook]))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var hasActiveFilter: Bool {
        !filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filter.kind != "all"
            || filter.book != initialBook
    }

    private var recordByID: [UUID: HoldingRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    private var recordsChangeToken: Int {
        var hasher = Hasher()
        hasher.combine(records.count)
        for r in records {
            hasher.combine(r.id)
            hasher.combine(r.grams.bitPattern)
            hasher.combine(r.purity.bitPattern)
            hasher.combine(r.unitPriceCNY.bitPattern)
            hasher.combine(r.totalPurchaseCost.bitPattern)
            hasher.combine(r.timestamp.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(r.disposition)
            hasher.combine(r.disposedAt?.timeIntervalSinceReferenceDate.bitPattern ?? 0)
            hasher.combine(r.disposalAmount.bitPattern)
            hasher.combine(r.bookName)
            hasher.combine(r.brand)
            hasher.combine(r.assetType)
        }
        return hasher.finalize()
    }

    private var statsEvents: [HoldingCalendarEvent] {
        let all = HoldingCalendarLogic.events(records, filter: filter)
        switch statsPeriod {
        case .month:
            return HoldingCalendarLogic.select(all, period: .month, date: calendarVM.focusedMonthDate)
        case .year:
            return HoldingCalendarLogic.select(all, period: .year, date: calendarVM.focusedMonthDate)
        case .all:
            return all
        }
    }

    private var statsTitle: String {
        switch statsPeriod {
        case .month: L10n.fmt("%@年%lld月", String(calendarVM.focusedYear), Int64(calendarVM.focusedMonth))
        case .year: L10n.fmt("%@年", String(calendarVM.focusedYear))
        case .all: L10n.tr("全部记录")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GoldCalendarHeaderView(
                        companionDays: calendarVM.companionStats.companionDays,
                        hasRecords: calendarVM.hasAnyRecordsInScope,
                        showTodayButton: !calendarVM.isViewingToday(),
                        hasActiveFilter: hasActiveFilter,
                        onTodayTap: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                calendarVM.jumpToToday()
                            }
                        },
                        onShareTap: { showingPoster = true },
                        onFilterTap: { showingFilter = true }
                    )

                    GoldCalendarSegmentedBar(activeTab: $calendarVM.activeTab)

                    switch calendarVM.activeTab {
                    case .month:
                        monthTabContent
                    case .year:
                        yearTabContent
                    case .stats:
                        statsTabContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(GoldTheme.background)
            .navigationTitle(L10n.tr("攒金日历"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isEmbeddedTab ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !isEmbeddedTab {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("关闭"), systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isEmbeddedTab {
                    Button { showingAdd = true } label: {
                        Label(L10n.tr("添加黄金"), systemImage: "plus").frame(minHeight: 24)
                    }
                    .buttonStyle(GoldPrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(GoldTheme.background)
                }
            }
            .modifier(EmbeddedCalendarTabBarSafeArea(isEmbeddedTab: isEmbeddedTab))
        }
        .tint(GoldTheme.gold)
        .foregroundStyle(GoldTheme.text)
        .presentationBackground(GoldTheme.background)
        .onAppear {
            if !didInitialize {
                filter.book = initialBook
                didInitialize = true
            }
            syncCalendarInputs()
        }
        .onChange(of: initialBook) { _, updatedBook in
            if isEmbeddedTab {
                filter.book = updatedBook
            }
        }
        .onChange(of: recordsChangeToken) { _, _ in
            syncCalendarInputs()
        }
        .onChange(of: filter) { _, _ in
            sectionExpansion = [:]
            syncCalendarInputs()
        }
        .onChange(of: marketBasis) { _, updatedBasis in
            if let quoteStore {
                model.applyExternalQuote(quoteStore.quote(for: updatedBasis), failed: quoteStore.isFailed(for: updatedBasis))
            }
            syncCalendarInputs()
        }
        .onChange(of: activeQuote) { _, latest in
            if let quoteStore {
                model.applyExternalQuote(latest, failed: quoteStore.isFailed(for: marketBasis))
            }
            syncCalendarInputs()
        }
        .onChange(of: calendarVM.selectedDate) { _, _ in
            sectionExpansion = [:]
        }
        .onChange(of: statsPeriod) { _, _ in
            sectionExpansion = [:]
        }
        .task(id: scenePhase) {
            guard !skipAutomaticNetworkSync else { return }
            if quoteStore == nil, scenePhase == .active {
                await model.start()
            }
        }
        .task(id: marketBasis) {
            guard !skipAutomaticNetworkSync else { return }
            await calendarVM.loadMarketData(for: marketBasis)
        }
        .task(id: calendarVM.focusedYear) {
            guard !skipAutomaticNetworkSync else { return }
            await calendarVM.ensureTemperatureCoverageIfNeeded(for: calendarVM.focusedYear)
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketCacheCleared)) { _ in
            Task { await calendarVM.clearCachedData() }
        }
        .sensoryFeedback(.selection, trigger: calendarVM.activeTab)
        .sensoryFeedback(.selection, trigger: calendarVM.selectedDayKey)
        .sheet(isPresented: $showingFilter) {
            HoldingCalendarFilterSheet(filter: $filter, books: books)
        }
        .sheet(isPresented: $showingAdd) {
            AddHoldingSheet(
                defaultUnitPrice: activeQuote?.cnyPerGram,
                date: calendarVM.selectedDate,
                book: filter.book ?? initialBook,
                marketBasis: marketBasis
            )
        }
        .sheet(isPresented: $showingYearMonthPicker) {
            GoldCalendarYearMonthPickerSheet(
                currentYear: calendarVM.focusedYear,
                currentMonth: calendarVM.focusedMonth
            ) { year, month in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    calendarVM.selectYearMonth(year: year, month: month)
                }
            }
        }
        .sheet(isPresented: $showingPoster) {
            if let posterSnapshot = makePosterSnapshot() {
                GoldCalendarPosterSheet(
                    snapshot: posterSnapshot,
                    initialMode: calendarVM.activeTab == .year ? .yearly : .monthly
                )
            }
        }
    }

    // MARK: - 1. 「月历」首屏内容

    @ViewBuilder
    private var monthTabContent: some View {
        if let monthSummary = calendarVM.focusedMonthSummary {
            GoldCalendarMonthReportCard(
                summary: monthSummary,
                companion: calendarVM.companionStats,
                layer: calendarVM.effectiveLayer,
                basis: marketBasis,
                hideAmounts: hideAmounts
            )
        }

        GoldCalendarMonthGridCard(
            year: calendarVM.focusedYear,
            month: calendarVM.focusedMonth,
            focusedMonthDate: calendarVM.focusedMonthDate,
            selectedDayKey: calendarVM.selectedDayKey,
            availableLayers: calendarVM.availableLayers,
            effectiveLayer: calendarVM.effectiveLayer,
            basis: marketBasis,
            hideAmounts: hideAmounts,
            snapshotProvider: { day in calendarVM.daySnapshot(for: day) },
            onSelectLayer: { layer in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    calendarVM.selectLayer(layer)
                }
            },
            onShiftMonth: { delta in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    calendarVM.shiftMonth(by: delta)
                }
            },
            onOpenYearMonthPicker: { showingYearMonthPicker = true },
            onSelectDay: { day in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    calendarVM.selectDate(day)
                }
            }
        )

        if let daySnap = calendarVM.selectedDaySnapshot {
            let lookup = recordByID
            GoldCalendarDayJournalCard(
                snapshot: daySnap,
                hasHoldingsInScope: calendarVM.hasAnyRecordsInScope,
                basis: marketBasis,
                hideAmounts: hideAmounts,
                recordLookup: { lookup[$0] },
                holdingsModel: model,
                onAddForDay: { showingAdd = true }
            )
        }
    }

    // MARK: - 2. 「年览」内容

    @ViewBuilder
    private var yearTabContent: some View {
        if let yearSnap = calendarVM.yearSnapshot {
            GoldCalendarYearOverviewView(
                yearSnapshot: yearSnap,
                hasHoldings: calendarVM.hasAnyRecordsInScope,
                basis: marketBasis,
                hideAmounts: hideAmounts,
                heatmapMode: $calendarVM.yearHeatmapMode,
                onShiftYear: { delta in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        calendarVM.shiftYear(by: delta)
                    }
                },
                onSelectMonth: { month in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        calendarVM.jumpToMonth(year: yearSnap.year, month: month)
                    }
                },
                onSelectDay: { dayKey in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        calendarVM.jumpToDay(dayKey)
                    }
                }
            )
        }
    }

    // MARK: - 3. 「统计」深度对账内容（完整保留原版统计与全量流水）

    private var statsTabContent: some View {
        let currentEvents = statsEvents
        let stats = HoldingCalendarLogic.stats(currentEvents, quote: activeQuote?.cnyPerGram)
        let lookup = recordByID

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(CalendarStatsScope.allCases) { scope in
                    let selected = (statsPeriod == scope)
                    Button {
                        statsPeriod = scope
                    } label: {
                        Text(scope.localizedTitle)
                            .font(.system(.caption, design: .rounded).weight(selected ? .bold : .medium))
                            .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(selected ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(
                                    selected ? Color.clear : GoldTheme.cardStroke,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                if statsPeriod != .all {
                    HStack(spacing: 4) {
                        Button {
                            if statsPeriod == .month { calendarVM.shiftMonth(by: -1) } else { calendarVM.shiftYear(by: -1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 28)
                                .background(GoldTheme.card, in: GoldTheme.circleShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("上一期间"))

                        Text(statsTitle)
                            .font(.system(.caption, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                            .lineLimit(1)

                        Button {
                            if statsPeriod == .month { calendarVM.shiftMonth(by: 1) } else { calendarVM.shiftYear(by: 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .frame(width: 28, height: 28)
                                .background(GoldTheme.card, in: GoldTheme.circleShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("下一期间"))
                    }
                }
            }

            valuationBasis
            statisticsCard(.purchases, stats: stats.purchases)
            statisticsCard(.sales, stats: stats.sales)
            statisticsCard(.gifts, stats: stats.gifts)

            if currentEvents.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(GoldTheme.textFaint)
                    Text(L10n.tr("当前所选范围暂无记录，可切换期间或调整筛选。"))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer()
                }
                .padding(14)
                .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            } else {
                Text(L10n.fmt("记录明细 · %lld 条", Int64(currentEvents.count)))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                    .padding(.top, 2)

                ForEach(currentEvents) { event in
                    statsEventRow(event, record: recordForEvent(event, in: lookup))
                }
            }
        }
    }

    // MARK: - 统计辅助视图与数据桥接

    private var noRecordsText: String {
        switch statsPeriod {
        case .month: L10n.tr("当月无记录")
        case .year: L10n.tr("当年无记录")
        case .all: L10n.tr("暂无记录")
        }
    }

    private var valuationBasis: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quote = activeQuote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 {
                Text(hideAmounts ? L10n.fmt("估值基准 · %@ · •••• 元/克", marketBasis.title) : L10n.fmt("估值基准 · %@ · %@ 元/克", marketBasis.title, quote.cnyPerGram.moneyText))
                Text(L10n.fmt("最新可用报价 · %@", quote.asOf.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLanguage.currentLocale))))
                    .foregroundStyle(GoldTheme.textFaint)
            } else {
                Text(L10n.fmt("%@报价暂不可用，预估金额与收益率显示为 —", marketBasis.title))
            }
        }
        .font(.caption)
        .foregroundStyle(GoldTheme.textSecondary)
    }

    private func statisticsCard(_ kind: CalendarStatisticsKind, stats: HoldingCalendarCategorySummary) -> some View {
        let expanded = sectionExpansion[kind] ?? (stats.count > 0)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { sectionExpansion[kind] = !expanded }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: kind.icon).font(.headline).foregroundStyle(GoldTheme.gold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title).font(.headline).foregroundStyle(GoldTheme.text)
                        Text(stats.count == 0 ? noRecordsText : hideAmounts ? L10n.tr("•• 笔记录") : L10n.fmt("%lld 笔 · %@ 克", Int64(stats.count), stats.grams.moneyText))
                            .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold()).foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(GoldTheme.holdingsCardShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stats.count == 0 ? L10n.fmt("%@，%@", kind.title, noRecordsText) : kind.title)
            .accessibilityValue(expanded ? L10n.tr("已展开") : L10n.tr("已收起"))
            .accessibilityHint(expanded ? L10n.tr("轻点以收起统计") : L10n.tr("轻点以展开统计"))

            if expanded {
                if stats.count == 0 {
                    Text(kind.emptyRangeHint)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .padding(.top, 14)
                } else {
                    statisticsDetails(kind, stats: stats).padding(.top, 18)
                }
            }
        }
        .padding(16)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func statisticsDetails(_ kind: CalendarStatisticsKind, stats: HoldingCalendarCategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                if kind == .sales {
                    metric(L10n.tr("实收金额(元)"), stats.proceeds.moneyText, prominent: true)
                    metric(L10n.tr("已实现收益(元)"), stats.profit?.signedMoneyText ?? "—", color: profitColor(stats.profit), prominent: true)
                } else {
                    metric(kind == .purchases ? L10n.tr("预估价值(元)") : L10n.tr("当前价值(元)"), stats.value?.moneyText ?? "—", prominent: true)
                    metric(
                        kind == .purchases ? L10n.tr("预估收益(元)") : L10n.tr("购入成本(元)"),
                        kind == .purchases ? stats.profit?.signedMoneyText ?? "—" : stats.cost.moneyText,
                        color: kind == .purchases ? profitColor(stats.profit) : GoldTheme.text,
                        prominent: true
                    )
                }
            }
            if kind != .gifts {
                HStack(spacing: 8) {
                    Text(kind == .sales ? L10n.tr("已实现收益率") : L10n.tr("预估收益率")).foregroundStyle(GoldTheme.textSecondary)
                    Text(hideAmounts ? "••••" : stats.profitPercent.map { $0.signedMoneyText + "%" } ?? "—")
                        .fontWeight(.semibold).monospacedDigit().foregroundStyle(profitColor(stats.profitPercent))
                }
                .font(.subheadline)
            }
            GoldTheme.cardStroke.frame(height: 1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), alignment: .leading)], alignment: .leading, spacing: 16) {
                metric(kind.countLabel, "\(stats.count)")
                metric(L10n.tr("总重量(克)"), stats.grams.moneyText)
                metric(L10n.tr("额外费用(元)"), stats.fees.moneyText)
                metric(L10n.tr("购入均价(元/克)"), stats.average.moneyText)
                if kind == .sales { metric(L10n.tr("卖出均价(元/克)"), stats.saleAverage.moneyText) }
                if kind != .gifts { metric(L10n.tr("购入总价(元)"), stats.cost.moneyText) }
            }
            Text(kind.explanation).font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }
    }

    private func profitColor(_ value: Double?) -> Color {
        guard let value else { return GoldTheme.textSecondary }
        return value > 0 ? GoldTheme.up : value < 0 ? GoldTheme.down : GoldTheme.text
    }

    private func metric(_ label: String, _ value: String, color: Color = GoldTheme.text, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Text(hideAmounts ? "••••" : value)
                .font(prominent ? .title3.weight(.semibold) : .body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statsEventRow(_ event: HoldingCalendarEvent, record: HoldingRecord?) -> some View {
        let assetType = record.map { GoldAssetType(rawValue: $0.assetType) ?? .other } ?? .other
        let rowContent = HStack(spacing: 10) {
            GoldAssetGlyph(type: assetType, size: 28, emphasized: true)
                .frame(width: 36, height: 36)
                .background(GoldTheme.background, in: GoldTheme.badgeShape)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                    Spacer()
                    Text(event.kind == "buy" ? L10n.tr("购入") : event.kind == "sold" ? L10n.tr("卖出") : L10n.tr("赠出"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(event.kind == "sold" ? GoldTheme.up : GoldTheme.gold)
                }
                HStack {
                    Text(hideAmounts
                        ? "••••"
                        : (event.kind == "sold"
                            ? L10n.fmt("%@ 克 · 实收 %@ 元", event.grams.moneyText, event.proceeds.moneyText)
                            : L10n.fmt("%@ 克 · 购入成本 %@ 元", event.grams.moneyText, event.cost.moneyText)))
                    Spacer()
                    Text(HoldingsSelection.dateText(event.date))
                }
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
            }
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

        if let record {
            NavigationLink {
                HoldingDetailView(
                    record: record,
                    model: model,
                    marketBasis: marketBasis,
                    embeddedInNavigationStack: true
                )
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private func recordForEvent(_ event: HoldingCalendarEvent, in lookup: [UUID: HoldingRecord]) -> HoldingRecord? {
        let prefixRemoved: String
        if event.id.hasPrefix("buy-") {
            prefixRemoved = String(event.id.dropFirst(4))
        } else if event.id.hasPrefix("dispose-") {
            prefixRemoved = String(event.id.dropFirst(8))
        } else {
            prefixRemoved = event.id
        }
        if let uuid = UUID(uuidString: prefixRemoved), let exact = lookup[uuid] {
            return exact
        }
        return lookup[event.purchaseID]
    }

    private func syncCalendarInputs() {
        guard !skipAutomaticNetworkSync else { return }
        calendarVM.syncInputs(
            items: records.map(\.calendarItem),
            filter: filter,
            basis: marketBasis,
            liveQuote: activeQuote
        )
    }

    private func makePosterSnapshot() -> GoldCalendarPosterSnapshot? {
        guard let yearSnap = calendarVM.yearSnapshot,
              let monthSummary = yearSnap.monthSummary(calendarVM.focusedMonth) else {
            return nil
        }
        return GoldCalendarPosterSnapshot(
            year: calendarVM.focusedYear,
            month: calendarVM.focusedMonth,
            monthSummary: monthSummary,
            yearSnapshot: yearSnap,
            companion: calendarVM.companionStats,
            basis: marketBasis,
            layer: calendarVM.effectiveLayer,
            maskSensitiveAmounts: true
        )
    }
}

struct HoldingCalendarFilterSheet: View {
    @Binding var filter: HoldingCalendarFilter
    let books: [String]
    @State private var draft = HoldingCalendarFilter()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.tr("关键词")).foregroundStyle(GoldTheme.textSecondary)
                    TextField(L10n.tr("购买渠道／买家／受赠人／品牌"), text: $draft.keyword)
                        .padding(16)
                        .background(GoldTheme.background, in: GoldTheme.rangeShape)
                    Text(L10n.tr("类型")).foregroundStyle(GoldTheme.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        option(L10n.tr("全部"), selected: draft.kind == "all") { draft.kind = "all" }
                        option(L10n.tr("在库"), selected: draft.kind == "holding") { draft.kind = "holding" }
                        option(L10n.tr("卖出"), selected: draft.kind == "sold") { draft.kind = "sold" }
                        option(L10n.tr("赠出"), selected: draft.kind == "gift") { draft.kind = "gift" }
                    }
                    Text(L10n.tr("账本")).foregroundStyle(GoldTheme.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                        option(L10n.tr("全部账本"), selected: draft.book == nil) { draft.book = nil }
                        ForEach(books, id: \.self) { book in
                            option(HoldingRecord.localizedBookName(book), selected: draft.book == book) { draft.book = book }
                        }
                    }
                }
                .padding(24)
            }
            .background(GoldTheme.card)
            .navigationTitle(L10n.tr("选择筛选项"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("关闭"), systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Button(L10n.tr("取消")) { dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                    Button(L10n.tr("确定")) { filter = draft; dismiss() }
                        .buttonStyle(GoldPrimaryButtonStyle())
                }
                .padding(20)
                .background(GoldTheme.card)
            }
        }
        .foregroundStyle(GoldTheme.text)
        .tint(GoldTheme.gold)
        .presentationDetents([.large])
        .onAppear { draft = filter }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(selected ? GoldTheme.gold : GoldTheme.text)
                .background(GoldTheme.background, in: GoldTheme.rangeShape)
                .overlay {
                    if selected {
                        GoldTheme.rangeShape.strokeBorder(GoldTheme.gold, lineWidth: 1)
                    }
                }
        }
    }
}

private struct EmbeddedCalendarTabBarSafeArea: ViewModifier {
    let isEmbeddedTab: Bool

    func body(content: Content) -> some View {
        if isEmbeddedTab {
            content.goldTabBarContentSafeArea()
        } else {
            content
        }
    }
}

private enum CalendarStatsScope: String, CaseIterable, Identifiable {
    case month = "当月"
    case year = "当年"
    case all = "全部"

    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .month: L10n.tr("当月")
        case .year: L10n.tr("当年")
        case .all: L10n.tr("全部")
        }
    }
}

private enum CalendarStatisticsKind: Hashable {
    case purchases, sales, gifts

    var title: String {
        switch self {
        case .purchases: L10n.tr("记金统计")
        case .sales: L10n.tr("卖出统计")
        case .gifts: L10n.tr("赠送统计")
        }
    }

    var recordName: String {
        switch self {
        case .purchases: L10n.tr("购入")
        case .sales: L10n.tr("卖出")
        case .gifts: L10n.tr("赠送")
        }
    }

    var countLabel: String {
        switch self {
        case .purchases: L10n.tr("购入笔数")
        case .sales: L10n.tr("卖出笔数")
        case .gifts: L10n.tr("赠送笔数")
        }
    }

    var emptyRangeHint: String {
        switch self {
        case .purchases: L10n.tr("当前所选范围没有购入记录，可切换期间或调整筛选。")
        case .sales: L10n.tr("当前所选范围没有卖出记录，可切换期间或调整筛选。")
        case .gifts: L10n.tr("当前所选范围没有赠送记录，可切换期间或调整筛选。")
        }
    }

    var icon: String {
        switch self {
        case .purchases: "tray.and.arrow.down"
        case .sales: "banknote"
        case .gifts: "gift"
        }
    }

    var explanation: String {
        switch self {
        case .purchases: L10n.tr("按所选期间购入黄金和最新可用金价估算，包含已赠卖部分；购入总价包含工费与其他成本，预估收益不代表已实现收益。")
        case .sales: L10n.tr("按所选期间卖出日期统计。已实现收益 = 实收金额 − 购入成本，购入成本包含分摊的工费与其他成本。")
        case .gifts: L10n.tr("按所选期间赠送日期统计。购入成本包含工费与其他成本；当前价值按最新可用金价估算，不计作投资收益。")
        }
    }
}
