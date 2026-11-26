import SwiftUI
import SwiftData

struct HoldingsView: View {
    let marketBasis: GoldMarketBasis
    let cloud: HoldingsCloud?
    let quoteStore: LiveGoldQuoteStore?
    let onOpenCalendar: (() -> Void)?
    let onOpenChartOverlay: (() -> Void)?
    let embedInNavigationStack: Bool
    @Query(sort: \HoldingRecord.timestamp, order: .reverse) private var records: [HoldingRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @AppStorage(OnboardingStorageKey.quickStartDismissed, store: .standard) private var quickStartDismissed = false
    @AppStorage(OnboardingStorageKey.visitedChartOverlay, store: .standard) private var visitedChartOverlay = false
    @AppStorage(OnboardingStorageKey.visitedCalendar, store: .standard) private var visitedCalendar = false
    @State private var model: HoldingsViewModel
    @State private var search = ""
    @State private var filter = HoldingFilter.all
    @State private var sort = HoldingSort.newest
    @State private var sheet: HoldingPageSheet?
    @State private var newBook = ""
    @State private var showingNewBook = false
    @State private var batch = false
    @State private var selection: Set<UUID> = []
    @State private var deleteTargets: [HoldingRecord] = []
    @State private var showingDelete = false
    @State private var transferTargets: [HoldingRecord] = []
    @State private var showingTransfer = false
    @State private var detail: HoldingRecord?
    @State private var pushedDetail: HoldingRecord?
    @State private var explaining = false
    @State private var profitBreakdown = false
    @State private var disposing: HoldingRecord?
    @State private var error: String?

    init(
        marketBasis: GoldMarketBasis = .domestic,
        cloud: HoldingsCloud? = nil,
        quoteStore: LiveGoldQuoteStore? = nil,
        onOpenCalendar: (() -> Void)? = nil,
        onOpenChartOverlay: (() -> Void)? = nil,
        embedInNavigationStack: Bool = true
    ) {
        self.cloud = cloud
        self.marketBasis = marketBasis
        self.quoteStore = quoteStore
        self.onOpenCalendar = onOpenCalendar
        self.onOpenChartOverlay = onOpenChartOverlay
        self.embedInNavigationStack = embedInNavigationStack
        let vm = HoldingsDesignPreview.makeModel(basis: marketBasis)
        if let quoteStore {
            vm.applyExternalQuote(quoteStore.quote(for: marketBasis), failed: quoteStore.isFailed(for: marketBasis))
        }
        _model = State(initialValue: vm)
    }

    private var books: [String] { Array(Set(savedBooks.components(separatedBy: "\n") + records.map(\.bookName) + ["默认账本"])).sorted() }
    private var bookRecords: [HoldingRecord] { records.filter { $0.bookName == book } }
    private var activeRecords: [HoldingRecord] { bookRecords.filter { $0.disposition == "holding" } }
    private var visibleRecords: [HoldingRecord] { HoldingsSelection.records(records, book: book, search: search, filter: filter, sort: sort, quote: model.quote?.cnyPerGram) }
    private var quickStartState: QuickStartChecklistState {
        QuickStartChecklistState(
            hasRecordedHolding: !records.isEmpty,
            hasViewedChartOverlay: visitedChartOverlay,
            hasVisitedCalendar: visitedCalendar
        )
    }

    var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    holdingsContent
                        .goldTabBarContentSafeArea()
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(item: $pushedDetail) { record in
                            HoldingDetailView(record: record, model: model, marketBasis: marketBasis, embeddedInNavigationStack: true)
                                .goldTabBarContentSafeArea()
                        }
                }
                .tint(GoldTheme.gold)
            } else {
                holdingsContent
            }
        }
    }

    private var holdingsContent: some View {
        ZStack {
            GoldTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                List {
                    if let cloud {
                        Text(cloud.status).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
                    }
                    if !HoldingsDesignPreview.isEnabled && quickStartState.shouldShowCard(dismissed: quickStartDismissed) {
                        OnboardingQuickStartCard(
                            state: quickStartState,
                            onSelectAction: handleQuickStartAction,
                            onDismiss: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    quickStartDismissed = true
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(GoldTheme.background)
                        .listRowSeparator(.hidden)
                    }
                    summary.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    GoldVaultCard(
                        summary: GoldVaultSummary(records: activeRecords),
                        hideAmounts: hideAmounts,
                        onAddTap: { sheet = .add }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(GoldTheme.background)
                    .listRowSeparator(.hidden)
                    HoldingsInsightsSection(
                        records: activeRecords,
                        currentGrams: activeRecords.reduce(0) { $0 + $1.grams },
                        referencePrice: model.quote?.cnyPerGram,
                        hideAmounts: hideAmounts
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(GoldTheme.background)
                    .listRowSeparator(.hidden)
                    filters.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    if visibleRecords.isEmpty {
                        emptyState.listRowInsets(EdgeInsets(top: 25, leading: 16, bottom: 0, trailing: 16))
                    }
                    ForEach(visibleRecords) { record in
                        HStack(spacing: 8) {
                            if batch {
                                Button {
                                    if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
                                } label: {
                                    Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(GoldTheme.gold)
                                }.buttonStyle(.plain).accessibilityLabel(L10n.tr("选择持仓"))
                            }
                            Button {
                                if batch {
                                    if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
                                } else if embedInNavigationStack {
                                    pushedDetail = record
                                } else {
                                    detail = record
                                }
                            } label: {
                                HoldingRowView(record: record, result: GoldReturnCalculator.calculate(record.returnInput, referencePrice: model.quote?.cnyPerGram), hideAmounts: hideAmounts)
                            }.buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(GoldTheme.background)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTargets = [record]; showingDelete = true } label: { Label(L10n.tr("删除"), systemImage: "trash") }
                            Button { transferTargets = [record]; showingTransfer = true } label: { Label(L10n.tr("迁移"), systemImage: "folder") }.tint(GoldTheme.textSecondary)
                            Button { disposing = record } label: { Label(L10n.tr("赠卖"), systemImage: "gift") }.tint(GoldTheme.gold)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .environment(\.defaultMinListRowHeight, 0)
                .listRowSpacing(0)
                if batch { batchBar.padding(.horizontal, 16).padding(.bottom, 10) }
            }
        }
        .task(id: scenePhase) {
            if quoteStore == nil, scenePhase == .active { await model.start() }
        }
        .onChange(of: quoteStore?.quote(for: marketBasis)) { _, latest in
            if let quoteStore {
                model.applyExternalQuote(latest, failed: quoteStore.isFailed(for: marketBasis))
            }
        }
        .onChange(of: quoteStore?.isFailed(for: marketBasis)) { _, failed in
            if let quoteStore {
                model.applyExternalQuote(quoteStore.quote(for: marketBasis), failed: failed ?? false)
            }
        }
        .onChange(of: marketBasis) { _, updatedBasis in
            if let quoteStore {
                model.applyExternalQuote(quoteStore.quote(for: updatedBasis), failed: quoteStore.isFailed(for: updatedBasis))
            }
        }
        .sensoryFeedback(.selection, trigger: book)
        .sensoryFeedback(.selection, trigger: hideAmounts)
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: sort)
        .sensoryFeedback(.selection, trigger: batch)
        .sheet(item: $sheet) { page in
            switch page {
            case .add: AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, marketBasis: marketBasis)
            case .calendar: HoldingsCalendarSheet(initialBook: book, hideAmounts: hideAmounts, marketBasis: marketBasis)
            case .calculator: GoldCalculatorSheet(model: model, marketBasis: marketBasis)
            case .overview: HoldingPortfolioSheet(records: activeRecords, model: model, basis: marketBasis)
            case .history: HoldingsHistorySheet(records: bookRecords.filter { $0.disposition != "holding" }, hideAmounts: hideAmounts)
            }
        }
        .sheet(item: $detail) { HoldingDetailView(record: $0, model: model, marketBasis: marketBasis) }
        .sheet(isPresented: $profitBreakdown) { GoldProfitBreakdownSheet(records: activeRecords, quote: model.quote, basis: marketBasis, hidden: hideAmounts, quoteFailed: model.quoteFailed) }
        .sheet(isPresented: $explaining) { GoldCalculationSheet(records: activeRecords, quote: model.quote, basis: marketBasis, hideAmounts: hideAmounts, quoteFailed: model.quoteFailed) }
        .sheet(item: $disposing) { record in DisposeHoldingSheet(record: record) }
        .alert(L10n.tr("新建账本"), isPresented: $showingNewBook) {
            TextField(L10n.tr("账本名称"), text: $newBook)
            Button(L10n.tr("取消"), role: .cancel) {}
            Button(L10n.tr("创建")) {
                let name = newBook.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                guard !name.isEmpty else { return }
                savedBooks = (books + [name]).joined(separator: "\n"); book = name; search = ""; selection = []
            }
        }
        .confirmationDialog(L10n.tr("删除所选持仓？"), isPresented: $showingDelete, titleVisibility: .visible) {
            Button(L10n.fmt("删除 %lld 条持仓", Int64(deleteTargets.count)), role: .destructive) { mutate { deleteTargets.forEach(context.delete) }; selection = [] }
        } message: { Text(L10n.tr("删除后无法恢复，购入记录也会移除。")) }
        .confirmationDialog(L10n.tr("迁移到其他账本"), isPresented: $showingTransfer, titleVisibility: .visible) {
            ForEach(books.filter { $0 != book }, id: \.self) { target in
                Button(HoldingRecord.localizedBookName(target)) { mutate { transferTargets.forEach { $0.bookName = target } }; selection = [] }
            }
            if books.count == 1 { Button(L10n.tr("先新建账本")) { newBook = ""; showingNewBook = true } }
        }
        .alert(L10n.tr("保存失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L10n.tr("知道了")) {} } message: { Text(error ?? L10n.tr("请重试")) }
        .onChange(of: book) { selection = []; filter = .all }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(books, id: \.self) { name in Button { book = name } label: { Label(HoldingRecord.localizedBookName(name), systemImage: name == book ? "checkmark" : "book.closed") } }
                Divider()
                Button(L10n.tr("新建账本"), systemImage: "plus") { newBook = ""; showingNewBook = true }
            } label: {
                HStack(spacing: 7) { Text(HoldingRecord.localizedBookName(book)).font(.system(size: 18, weight: .bold)).lineLimit(1); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12)) }
                .foregroundStyle(GoldTheme.text)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                TextField(L10n.tr("搜索"), text: $search).accessibilityLabel(L10n.tr("搜索品牌或备注"))
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(L10n.tr("清除搜索")) }
            }
            .font(.system(size: 13)).foregroundStyle(GoldTheme.textSecondary)
            .padding(.horizontal, 12).frame(width: 126, height: 32).background(GoldTheme.card, in: GoldTheme.capsuleShape)
        }.frame(minHeight: 34)
    }

    private var summary: some View {
        let stats = model.returns(for: activeRecords)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.tr("现在卖预计到手")).font(.subheadline)
                Text(L10n.tr("估算")).font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                Button { hideAmounts.toggle() } label: { Image(systemName: hideAmounts ? "eye.slash" : "eye") }
                    .accessibilityLabel(hideAmounts ? L10n.tr("显示金额") : L10n.tr("隐藏金额")).frame(width: 44, height: 32)
            }.foregroundStyle(GoldTheme.text)
            Button { if !activeRecords.isEmpty { sheet = .overview } } label: {
                Text(GoldReturnPresentation.money(stats?.proceeds, hidden: hideAmounts))
                    .font(.system(size: 39, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(GoldTheme.gold)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: stats?.proceeds)
                    .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { if !activeRecords.isEmpty { profitBreakdown = true } } label: {
                HStack(spacing: 8) {
                    Text(L10n.fmt("真实盈亏 %@", GoldReturnPresentation.money(stats?.profit, hidden: hideAmounts, signed: true)))
                    Spacer(minLength: 4)
                    Text(GoldReturnPresentation.percent(stats?.profitPercent, hidden: hideAmounts))
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                }.font(.subheadline).foregroundStyle(hideAmounts ? GoldTheme.text : (stats?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint(L10n.tr("查看盈亏来源拆解"))
            HStack {
                Text(hideAmounts ? L10n.tr("总持有 •••• g") : L10n.fmt("总持有 %@ g", (stats?.grams ?? 0).moneyText))
                Spacer()
                Text(L10n.fmt("总投入 %@", GoldReturnPresentation.money(stats?.totalCost, hidden: hideAmounts)))
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
            if !activeRecords.isEmpty {
                Button { explaining = true } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(GoldReturnPresentation.status(price: model.quote?.cnyPerGram, breakEven: stats?.breakEvenPrice, hidden: hideAmounts)).font(.subheadline.bold())
                            Spacer(minLength: 4); Image(systemName: "info.circle")
                        }.foregroundStyle(GoldTheme.gold)
                        Text(L10n.fmt("当前参考 %@ / g · 保本 %@ / g", GoldReturnPresentation.money(model.quote?.cnyPerGram, hidden: hideAmounts), GoldReturnPresentation.money(stats?.breakEvenPrice, hidden: hideAmounts)))
                            .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                    }
                }.buttonStyle(.plain)
                Text(L10n.fmt("今日价格变化带来的持仓变化 %@", GoldReturnPresentation.money(stats?.todayChange, hidden: hideAmounts, signed: true)))
                    .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
            }
            Text(GoldReturnPresentation.quoteStatus(model.quote, basis: marketBasis, failed: model.quoteFailed)).font(.caption2).foregroundStyle(GoldTheme.textSecondary)
            HStack(spacing: 12) {
                action(activeRecords.isEmpty ? L10n.tr("记第一笔黄金") : L10n.tr("记一笔"), filled: true) { sheet = .add }
                action(L10n.tr("买前算一算"), filled: false) { sheet = .calculator }
            }
            HStack {
                Button(L10n.tr("记金日历"), systemImage: "calendar") {
                    visitedCalendar = true
                    if let onOpenCalendar { onOpenCalendar() } else { sheet = .calendar }
                }
                Spacer()
                Button(L10n.tr("赠卖记录"), systemImage: "clock") { sheet = .history }
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary).frame(minHeight: 32)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            // Keep buttons independent within this List row.
            .buttonStyle(.plain)
            .listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }

    private func action(_ title: String, filled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).frame(height: 44)
            .foregroundStyle(filled ? GoldTheme.onGold : GoldTheme.gold)
            .background(filled ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold, lineWidth: 1)) }.buttonStyle(.plain)
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    filterMenus
                    Spacer(minLength: 8)
                    batchToggle
                }
                VStack(alignment: .leading, spacing: 8) {
                    filterMenus
                    batchToggle.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text(batch ? L10n.tr("勾选记录后，可批量迁移或删除") : L10n.tr("左滑单条记录，可赠卖、迁移或删除"))
                .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
        }.listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }

    private var filterMenus: some View {
        HStack(spacing: 8) {
            Menu { Picker(L10n.tr("筛选"), selection: $filter) { ForEach(HoldingFilter.allCases, id: \.self) { Text($0.localizedTitle).tag($0) } } } label: { filterLabel(filter == .all ? L10n.tr("筛选") : filter.localizedTitle) }
            Menu { Picker(L10n.tr("排序"), selection: $sort) { ForEach(HoldingSort.allCases, id: \.self) { Text($0.localizedTitle).tag($0) } } } label: { filterLabel(L10n.tr("排序")) }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var batchToggle: some View {
        Button { batch.toggle(); selection = [] } label: {
            HStack(spacing: 6) {
                Image(systemName: batch ? "checkmark" : "checklist")
                Text(batch ? L10n.tr("完成") : L10n.tr("批量管理")).lineLimit(1)
            }.fixedSize(horizontal: true, vertical: false)
                .font(.system(.subheadline).weight(.semibold))
                .padding(.horizontal, 12).frame(minWidth: 92, minHeight: 44)
                .foregroundStyle(batch ? GoldTheme.onGold : GoldTheme.goldSoft)
                .background(batch ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(batch ? GoldTheme.gold : GoldTheme.cardStroke, lineWidth: 1))
                .contentShape(GoldTheme.capsuleShape)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(batch ? L10n.tr("完成批量管理") : L10n.tr("批量管理"))
        .accessibilityHint(batch ? L10n.tr("退出批量管理并取消勾选") : L10n.tr("选择多条持仓进行迁移或删除"))
    }

    private func filterLabel(_ title: String) -> some View {
        HStack(spacing: 6) { Text(title); Image(systemName: "chevron.down").font(.caption2) }
            .font(.system(.subheadline).weight(.medium)).foregroundStyle(GoldTheme.text)
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
            .contentShape(GoldTheme.capsuleShape)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            GoldMoneyBagShape().fill(GoldTheme.gold).frame(width: 30, height: 33)
            Text(activeRecords.isEmpty ? L10n.tr("还没有记金记录") : L10n.tr("没有符合条件的记录")).font(.subheadline).foregroundStyle(GoldTheme.text)
            Text(activeRecords.isEmpty ? L10n.tr("从第一笔黄金开始，慢慢攒下你的底气") : L10n.tr("试试其他关键词或筛选条件")).font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }.frame(maxWidth: .infinity).listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }
    private var batchBar: some View {
        HStack {
            Button(L10n.tr("全选")) { selection = Set(visibleRecords.map(\.id)) }
            Text(L10n.fmt("已选 %lld 笔", Int64(selection.count))).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Spacer()
            Button(L10n.tr("迁移")) { transferTargets = activeRecords.filter { selection.contains($0.id) }; showingTransfer = true }.disabled(selection.isEmpty)
            Button(L10n.tr("删除"), role: .destructive) { deleteTargets = activeRecords.filter { selection.contains($0.id) }; showingDelete = true }.disabled(selection.isEmpty)
        }.font(.subheadline).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
    private func handleQuickStartAction(_ action: QuickStartAction) {
        switch action {
        case .recordFirstHolding:
            sheet = .add
        case .viewChartOverlay:
            visitedChartOverlay = true
            onOpenChartOverlay?()
        case .visitCalendar:
            visitedCalendar = true
            if let onOpenCalendar {
                onOpenCalendar()
            } else {
                sheet = .calendar
            }
        }
    }

    private func mutate(_ operation: () -> Void) { operation(); do { try context.save() } catch { context.rollback(); self.error = L10n.tr("未能保存修改，请重试。") } }
}

enum HoldingPageSheet: String, Identifiable { case add, calendar, history, calculator, overview; var id: String { rawValue } }

struct HoldingRowView: View {
    let record: HoldingRecord
    let result: GoldReturnResult?
    let hideAmounts: Bool
    var body: some View {
        let assetType = GoldAssetType(rawValue: record.assetType) ?? .other
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GoldAssetGlyph(type: assetType, size: 26, emphasized: true)
                Text(record.displayName).font(.subheadline.bold()).lineLimit(1)
                if let holder = record.holdingHolder {
                    HoldingHolderAvatar(holder: holder, size: 24, emphasized: true)
                }
                Spacer()
                Text(HoldingsSelection.dateText(record.timestamp)).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(GoldTheme.textSecondary)
            }
            HStack {
                Text(hideAmounts ? L10n.tr("•••• g · 总投入 ••••") : L10n.fmt("%@ g · 总投入 ¥%@", record.grams.moneyText, record.totalPurchaseCost.moneyText))
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
            HStack {
                Text(L10n.tr("现在卖预计到手")).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                Spacer(minLength: 4)
                Text(GoldReturnPresentation.money(result?.proceeds, hidden: hideAmounts)).font(.subheadline.bold()).monospacedDigit()
            }
            HStack {
                Text(L10n.fmt("真实盈亏 %@", GoldReturnPresentation.money(result?.profit, hidden: hideAmounts, signed: true)))
                Spacer(minLength: 4)
                Text(GoldReturnPresentation.percent(result?.profitPercent, hidden: hideAmounts))
            }.font(.caption).foregroundStyle((result?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
        }.foregroundStyle(GoldTheme.text).padding(16)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
}
