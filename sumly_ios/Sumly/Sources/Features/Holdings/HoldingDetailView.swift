import SwiftUI

struct HoldingDetailView: View {
    let record: HoldingRecord
    let model: HoldingsViewModel
    let marketBasis: GoldMarketBasis
    var embeddedInNavigationStack: Bool = false
    @AppStorage("holdings.hideAmounts") private var hidden = false
    @Environment(\.dismiss) private var dismiss
    @State private var page: DetailPage?
    private enum DetailPage: String, Identifiable { case calculation, scenario, edit, alerts, sale; var id: String { rawValue } }
    private var result: GoldReturnResult? { GoldReturnCalculator.calculate(record.returnInput, referencePrice: model.quote?.cnyPerGram) }
    private var displayedProfit: Double? {
        switch record.disposition {
        case "sold": record.disposalAmount - record.totalPurchaseCost
        case "gift": record.totalPurchaseCost
        default: result?.profit
        }
    }
    var body: some View {
        Group {
            if embeddedInNavigationStack {
                detailScroll
            } else {
                NavigationStack {
                    detailScroll
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .sheet(item: $page) { page in
            switch page {
            case .calculation: GoldCalculationSheet(records: [record], quote: model.quote, basis: marketBasis, hideAmounts: hidden, quoteFailed: model.quoteFailed)
            case .scenario: GoldScenarioSheet(record: record, referencePrice: model.quote?.cnyPerGram)
            case .edit: AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, marketBasis: marketBasis, editing: record)
            case .alerts: HoldingAlertSheet(record: record, basis: marketBasis)
            case .sale: DisposeHoldingSheet(record: record)
            }
        }
    }

    private var detailScroll: some View {
        let assetLabel = GoldAssetType(rawValue: record.assetType)?.displayName ?? record.assetType
        let holdDays = max(0, Calendar.current.dateComponents([.day], from: record.timestamp, to: .now).day ?? 0)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(record.displayName).font(.title2.bold())
                        if let holder = record.holdingHolder {
                            HoldingHolderBadge(holder: holder)
                        }
                    }
                    Text(L10n.fmt("%@ · %@ 购入 · 持有 %lld 天", assetLabel, HoldingsSelection.dateText(record.timestamp), Int64(holdDays)))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(record.disposition == "sold" ? L10n.tr("实际盈亏") : record.disposition == "gift" ? L10n.tr("赠送成本") : L10n.tr("真实盈亏")); Spacer(); Text(record.disposition == "holding" ? L10n.tr("估算") : L10n.tr("已记录")).font(.caption).foregroundStyle(GoldTheme.textSecondary) }
                    Text(GoldReturnPresentation.money(displayedProfit, hidden: hidden, signed: record.disposition != "gift"))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(hidden || record.disposition == "gift" ? GoldTheme.text : (displayedProfit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    if record.disposition == "holding" {
                        HStack { Text(L10n.tr("真实收益率")); Spacer(); Text(GoldReturnPresentation.percent(result?.profitPercent, hidden: hidden)) }
                            .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                        HStack { Text(L10n.tr("账面价值")); Spacer(); Text(GoldReturnPresentation.money(result?.bookValue, hidden: hidden)) }
                            .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                        Button(L10n.tr("怎么算的？"), systemImage: "info.circle") { page = .calculation }.font(.subheadline).foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).goldCard()
                if record.disposition != "gift" {
                    GoldProfitBreakdownCard(breakdown: record.disposition == "sold"
                        ? GoldProfitBreakdown.sale(totalCost: record.totalPurchaseCost, proceeds: record.disposalAmount)
                        : GoldProfitBreakdown.estimate([record.returnInput], referencePrice: model.quote?.cnyPerGram),
                        records: [record], hidden: hidden, actual: record.disposition == "sold", showTotal: false, unconfiguredRecovery: record.disposition == "holding" && record.returnInput.rule.isDefault)
                }
                if record.disposition == "holding" {
                    HStack(alignment: .top) {
                        GoldResultMetric(title: L10n.tr("现在卖预计到手"), value: GoldReturnPresentation.money(result?.proceeds, hidden: hidden))
                        GoldResultMetric(title: L10n.tr("真实保本金价 / g"), value: GoldReturnPresentation.money(result?.breakEvenPrice, hidden: hidden), color: GoldTheme.gold)
                    }
                    Text(GoldReturnPresentation.status(price: model.quote?.cnyPerGram, breakEven: result?.breakEvenPrice, hidden: hidden))
                        .font(.subheadline).foregroundStyle(GoldTheme.gold)
                    HStack {
                        GoldResultMetric(title: L10n.tr("总投入"), value: GoldReturnPresentation.money(record.totalPurchaseCost, hidden: hidden))
                        GoldResultMetric(title: L10n.tr("预计回收单价 / g"), value: GoldReturnPresentation.money(result?.recoveryUnitPrice, hidden: hidden))
                    }
                    Text(GoldReturnPresentation.quoteStatus(model.quote, basis: marketBasis, failed: model.quoteFailed))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    Text(L10n.tr("预计到手受纯度与回收规则影响，真实成交价以渠道报价为准。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }
                if record.disposition != "holding" { Text(record.disposition == "sold" ? L10n.tr("这笔黄金已卖出，已从当前持仓中移除。") : L10n.tr("这笔黄金已赠送，已从当前持仓中移除。")).foregroundStyle(GoldTheme.gold) }
            }.padding(16).foregroundStyle(GoldTheme.text)
        }.background(GoldTheme.background)
            .safeAreaInset(edge: .bottom) {
                if record.disposition == "holding" {
                    VStack(spacing: 10) {
                        HStack {
                            Button(L10n.tr("情景测算"), systemImage: "slider.horizontal.3") { page = .scenario }.buttonStyle(GoldPrimaryButtonStyle())
                            Button(L10n.tr("设置提醒"), systemImage: "bell") { page = .alerts }.buttonStyle(GoldPrimaryButtonStyle())
                        }
                        HStack {
                            Button(L10n.tr("编辑")) { page = .edit }; Spacer(); Button(L10n.tr("标记卖出")) { page = .sale }
                        }.font(.subheadline).foregroundStyle(GoldTheme.gold).padding(.horizontal, 16).frame(minHeight: 38)
                    }.padding(16).background(GoldTheme.background)
                }
            }
            .navigationTitle(L10n.tr("持仓详情")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

struct HoldingPortfolioSheet: View {
    let records: [HoldingRecord]
    let model: HoldingsViewModel
    let basis: GoldMarketBasis
    @AppStorage("holdings.hideAmounts") private var hidden = false
    @Environment(\.dismiss) private var dismiss
    @State private var selected: HoldingRecord?
    @State private var explanation = false
    @State private var profitBreakdown = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let result = model.returns(for: records)
                    GoldResultMetric(title: L10n.tr("现在卖预计到手 · 估算"), value: GoldReturnPresentation.money(result?.proceeds, hidden: hidden), color: GoldTheme.gold)
                    Button { profitBreakdown = true } label: {
                    GoldResultMetric(title: L10n.tr("真实盈亏 · 查看来源 ›"), value: GoldReturnPresentation.money(result?.profit, hidden: hidden, signed: true), color: (result?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    }.buttonStyle(.plain)
                    HStack {
                        GoldResultMetric(title: L10n.tr("总投入"), value: GoldReturnPresentation.money(result?.totalCost, hidden: hidden))
                        GoldResultMetric(title: L10n.tr("组合真实保本价 / g"), value: GoldReturnPresentation.money(result?.breakEvenPrice, hidden: hidden))
                    }
                    Button(L10n.tr("怎么算的？")) { explanation = true }.foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                    ForEach(records) { record in
                        Button { selected = record } label: {
                            HoldingRowView(record: record, result: GoldReturnCalculator.calculate(record.returnInput, referencePrice: model.quote?.cnyPerGram), hideAmounts: hidden)
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }.background(GoldTheme.background).navigationTitle(L10n.tr("全部持仓收益")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
        }.sheet(item: $selected) { HoldingDetailView(record: $0, model: model, marketBasis: basis) }
            .sheet(isPresented: $profitBreakdown) { GoldProfitBreakdownSheet(records: records, quote: model.quote, basis: basis, hidden: hidden, quoteFailed: model.quoteFailed) }
            .sheet(isPresented: $explanation) { GoldCalculationSheet(records: records, quote: model.quote, basis: basis, hideAmounts: hidden, quoteFailed: model.quoteFailed) }
    }
}
