import SwiftUI
import SwiftData

struct HoldingsView: View {
    let marketBasis: GoldMarketBasis
    let cloud: HoldingsCloud?
    @Query(sort: \HoldingRecord.timestamp, order: .reverse) private var records: [HoldingRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
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
    @State private var explaining = false
    @State private var profitBreakdown = false
    @State private var disposing: HoldingRecord?
    @State private var error: String?

    init(marketBasis: GoldMarketBasis = .domestic, cloud: HoldingsCloud? = nil) {
        self.cloud = cloud
        self.marketBasis = marketBasis
        _model = State(initialValue: HoldingsDesignPreview.makeModel(basis: marketBasis))
    }

    private var books: [String] { Array(Set(savedBooks.components(separatedBy: "\n") + records.map(\.bookName) + ["默认账本"])).sorted() }
    private var bookRecords: [HoldingRecord] { records.filter { $0.bookName == book } }
    private var activeRecords: [HoldingRecord] { bookRecords.filter { $0.disposition == "holding" } }
    private var visibleRecords: [HoldingRecord] { HoldingsSelection.records(records, book: book, search: search, filter: filter, sort: sort, quote: model.quote?.cnyPerGram) }

    var body: some View {
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
                    summary.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    filters.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    if visibleRecords.isEmpty {
                        emptyState.listRowInsets(EdgeInsets(top: 25, leading: 16, bottom: 0, trailing: 16))
                    }
                    ForEach(visibleRecords) { record in
                        HStack(spacing: 8) {
                            if batch {
                                Button { if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) } } label: {
                                    Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(GoldTheme.gold)
                                }.buttonStyle(.plain).accessibilityLabel("选择持仓")
                            }
                            Button { if batch { if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) } } else { detail = record } } label: {
                                HoldingRowView(record: record, result: GoldReturnCalculator.calculate(record.returnInput, referencePrice: model.quote?.cnyPerGram), hideAmounts: hideAmounts)
                            }.buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(GoldTheme.background)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTargets = [record]; showingDelete = true } label: { Label("删除", systemImage: "trash") }
                            Button { transferTargets = [record]; showingTransfer = true } label: { Label("迁移", systemImage: "folder") }.tint(GoldTheme.textSecondary)
                            Button { disposing = record } label: { Label("赠卖", systemImage: "gift") }.tint(GoldTheme.gold)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .listRowSpacing(0)
                if batch { batchBar.padding(.horizontal, 16).padding(.bottom, 10) }
            }
        }
        .task(id: scenePhase) { if scenePhase == .active { await model.start() } }
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
        .alert("新建账本", isPresented: $showingNewBook) {
            TextField("账本名称", text: $newBook)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let name = newBook.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
                guard !name.isEmpty else { return }
                savedBooks = (books + [name]).joined(separator: "\n"); book = name; search = ""; selection = []
            }
        }
        .confirmationDialog("删除所选持仓？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除 \(deleteTargets.count) 条持仓", role: .destructive) { mutate { deleteTargets.forEach(context.delete) }; selection = [] }
        } message: { Text("删除后无法恢复，购入记录也会移除。") }
        .confirmationDialog("迁移到其他账本", isPresented: $showingTransfer, titleVisibility: .visible) {
            ForEach(books.filter { $0 != book }, id: \.self) { target in
                Button(target) { mutate { transferTargets.forEach { $0.bookName = target } }; selection = [] }
            }
            if books.count == 1 { Button("先新建账本") { newBook = ""; showingNewBook = true } }
        }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "请重试") }
        .onChange(of: book) { selection = []; filter = .all }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(books, id: \.self) { name in Button { book = name } label: { Label(name, systemImage: name == book ? "checkmark" : "book.closed") } }
                Divider()
                Button("新建账本", systemImage: "plus") { newBook = ""; showingNewBook = true }
            } label: {
                HStack(spacing: 7) { Text(book).font(.system(size: 18, weight: .bold)).lineLimit(1); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12)) }
                .foregroundStyle(GoldTheme.text)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                TextField("搜索", text: $search).accessibilityLabel("搜索品牌或备注")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            }
            .font(.system(size: 13)).foregroundStyle(GoldTheme.textSecondary)
            .padding(.horizontal, 12).frame(width: 126, height: 32).background(GoldTheme.card, in: GoldTheme.capsuleShape)
        }.frame(minHeight: 34)
    }

    private var summary: some View {
        let stats = model.returns(for: activeRecords)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("现在卖预计到手").font(.subheadline)
                Text("估算").font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                Button { hideAmounts.toggle() } label: { Image(systemName: hideAmounts ? "eye.slash" : "eye") }
                    .accessibilityLabel(hideAmounts ? "显示金额" : "隐藏金额").frame(width: 44, height: 32)
            }.foregroundStyle(GoldTheme.text)
            Button { if !activeRecords.isEmpty { sheet = .overview } } label: {
                Text(GoldReturnPresentation.money(stats?.proceeds, hidden: hideAmounts))
                    .font(.system(size: 39, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(GoldTheme.gold)
                    .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button { if !activeRecords.isEmpty { profitBreakdown = true } } label: {
                HStack(spacing: 8) {
                    Text("真实盈亏 " + GoldReturnPresentation.money(stats?.profit, hidden: hideAmounts, signed: true))
                    Spacer(minLength: 4)
                    Text(GoldReturnPresentation.percent(stats?.profitPercent, hidden: hideAmounts))
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                }.font(.subheadline).foregroundStyle(hideAmounts ? GoldTheme.text : (stats?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("查看盈亏来源拆解")
            HStack {
                Text(hideAmounts ? "总持有 •••• g" : "总持有 \((stats?.grams ?? 0).moneyText) g")
                Spacer()
                Text("总投入 " + GoldReturnPresentation.money(stats?.totalCost, hidden: hideAmounts))
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
            if !activeRecords.isEmpty {
                Button { explaining = true } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(GoldReturnPresentation.status(price: model.quote?.cnyPerGram, breakEven: stats?.breakEvenPrice, hidden: hideAmounts)).font(.subheadline.bold())
                            Spacer(minLength: 4); Image(systemName: "info.circle")
                        }.foregroundStyle(GoldTheme.gold)
                        Text("当前参考 " + GoldReturnPresentation.money(model.quote?.cnyPerGram, hidden: hideAmounts) + " / g · 保本 " + GoldReturnPresentation.money(stats?.breakEvenPrice, hidden: hideAmounts) + " / g")
                            .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                    }
                }.buttonStyle(.plain)
                Text("今日价格变化带来的持仓变化 " + GoldReturnPresentation.money(stats?.todayChange, hidden: hideAmounts, signed: true))
                    .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
            }
            Text(GoldReturnPresentation.quoteStatus(model.quote, basis: marketBasis, failed: model.quoteFailed)).font(.caption2).foregroundStyle(GoldTheme.textSecondary)
            HStack(spacing: 12) {
                action(activeRecords.isEmpty ? "记第一笔黄金" : "记一笔", filled: true) { sheet = .add }
                action("买前算一算", filled: false) { sheet = .calculator }
            }
            HStack {
                Button("记金日历", systemImage: "calendar") { sheet = .calendar }
                Spacer()
                Button("赠卖记录", systemImage: "clock") { sheet = .history }
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
            Text(batch ? "勾选记录后，可批量迁移或删除" : "左滑单条记录，可赠卖、迁移或删除")
                .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
        }.listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }

    private var filterMenus: some View {
        HStack(spacing: 8) {
            Menu { Picker("筛选", selection: $filter) { ForEach(HoldingFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { filterLabel(filter == .all ? "筛选" : filter.rawValue) }
            Menu { Picker("排序", selection: $sort) { ForEach(HoldingSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { filterLabel("排序") }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var batchToggle: some View {
        Button { batch.toggle(); selection = [] } label: {
            HStack(spacing: 6) {
                Image(systemName: batch ? "checkmark" : "checklist")
                Text(batch ? "完成" : "批量管理").lineLimit(1)
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
        .accessibilityLabel(batch ? "完成批量管理" : "批量管理")
        .accessibilityHint(batch ? "退出批量管理并取消勾选" : "选择多条持仓进行迁移或删除")
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
            Text(activeRecords.isEmpty ? "还没有记金记录" : "没有符合条件的记录").font(.subheadline).foregroundStyle(GoldTheme.text)
            Text(activeRecords.isEmpty ? "从第一笔黄金开始，慢慢攒下你的底气" : "试试其他关键词或筛选条件").font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }.frame(maxWidth: .infinity).listRowBackground(GoldTheme.background).listRowSeparator(.hidden)
    }
    private var batchBar: some View {
        HStack {
            Button("全选") { selection = Set(visibleRecords.map(\.id)) }
            Text("已选 \(selection.count) 笔").font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Spacer()
            Button("迁移") { transferTargets = activeRecords.filter { selection.contains($0.id) }; showingTransfer = true }.disabled(selection.isEmpty)
            Button("删除", role: .destructive) { deleteTargets = activeRecords.filter { selection.contains($0.id) }; showingDelete = true }.disabled(selection.isEmpty)
        }.font(.subheadline).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
    private func mutate(_ operation: () -> Void) { operation(); do { try context.save() } catch { context.rollback(); self.error = "未能保存修改，请重试。" } }
}

enum HoldingPageSheet: String, Identifiable { case add, calendar, history, calculator, overview; var id: String { rawValue } }

struct HoldingRowView: View {
    let record: HoldingRecord
    let result: GoldReturnResult?
    let hideAmounts: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(record.displayName).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text(HoldingsSelection.dateText(record.timestamp)).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(GoldTheme.textSecondary)
            }
            HStack {
                Text(hideAmounts ? "•••• g · 总投入 ••••" : "\(record.grams.moneyText) g · 总投入 ¥\(record.totalPurchaseCost.moneyText)")
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
            HStack {
                Text("现在卖预计到手").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                Spacer(minLength: 4)
                Text(GoldReturnPresentation.money(result?.proceeds, hidden: hideAmounts)).font(.subheadline.bold()).monospacedDigit()
            }
            HStack {
                Text("真实盈亏 " + GoldReturnPresentation.money(result?.profit, hidden: hideAmounts, signed: true))
                Spacer(minLength: 4)
                Text(GoldReturnPresentation.percent(result?.profitPercent, hidden: hideAmounts))
            }.font(.caption).foregroundStyle((result?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
        }.foregroundStyle(GoldTheme.text).padding(16)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
}
