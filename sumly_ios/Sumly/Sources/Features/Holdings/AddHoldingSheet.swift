import SwiftUI
import SwiftData

struct AddHoldingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let marketBasis: GoldMarketBasis
    @State private var draft: HoldingDraft
    @State private var purchasePrice: HoldingPurchasePriceModel
    @State private var timestamp: Date
    @State private var advanced = false
    private let targetBook: String?
    private let editing: HoldingRecord?
    private let onSaved: (() -> Void)?
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @State private var errorMessage: String?

    init(defaultUnitPrice: Double?, date: Date = .now, book: String? = nil, marketBasis: GoldMarketBasis = .domestic,
         editing: HoldingRecord? = nil, seed: HoldingDraft? = nil, onSaved: (() -> Void)? = nil) {
        targetBook = book; self.editing = editing; self.onSaved = onSaved; self.marketBasis = marketBasis
        let day = editing?.timestamp ?? min(date, .now)
        _timestamp = State(initialValue: day)
        let values = editing.map(HoldingDraft.init(record:)) ?? seed ?? HoldingDraft()
        _draft = State(initialValue: values)
        let priceModel = HoldingPurchasePriceModel(date: day, basis: marketBasis, initialPrice: defaultUnitPrice,
            service: BackendGoldPriceService(instrumentID: marketBasis.instrumentID))
        if editing != nil || seed != nil { priceModel.editPrice(values.priceText) }
        _purchasePrice = State(initialValue: priceModel)
    }

    private var result: GoldReturnResult? {
        draft.input.flatMap { GoldReturnCalculator.calculate($0, referencePrice: nil) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("黄金类型", selection: $draft.assetType) {
                        ForEach(GoldAssetType.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    GoldInputField(title: "克重（g）", text: $draft.gramsText, placeholder: "例如 30")
                    Picker("购入价格方式", selection: $draft.costMode) {
                        ForEach(HoldingCostMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if draft.costMode == .total {
                        GoldInputField(title: "购买总价（元）· 手动总投入", text: $draft.totalText, placeholder: "实际支付总额")
                        Text("总价已包含工费与其他成本，不会重复计入。")
                            .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        if let result { Text("综合单价 ¥\(result.comprehensiveUnitCost.moneyText) / g").font(.caption).foregroundStyle(GoldTheme.gold) }
                    } else {
                        GoldInputField(title: "裸金购入单价（元/克）", text: Binding(get: { purchasePrice.priceText }, set: {
                            purchasePrice.editPrice($0); draft.priceText = $0
                        }), placeholder: "实际购入单价")
                        priceReferenceStatus
                        if let result { Text("总投入 ¥\(result.totalCost.moneyText)").font(.caption).foregroundStyle(GoldTheme.gold) }
                    }
                    DatePicker("购买日期", selection: Binding(get: { timestamp }, set: {
                        timestamp = $0; purchasePrice.selectDate($0)
                    }), in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN")).font(.subheadline).foregroundStyle(GoldTheme.text)
                    DisclosureGroup("完善真实收益信息", isExpanded: $advanced) {
                        GoldAdvancedFields(draft: $draft).padding(.top, 12)
                    }.foregroundStyle(GoldTheme.gold)
                    Text("默认纯度 \(draft.purityText)%，回收参数可在高级信息中修改。")
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    if let result {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("预计真实保本金价").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            Text("¥\(result.breakEvenPrice.moneyText) / g").font(.title2.bold()).monospacedDigit().foregroundStyle(GoldTheme.gold)
                            Text("按当前回收规则估算，成交价以渠道实际报价为准。")
                                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).goldCard()
                    } else {
                        Text("填写有效克重和购入价格后，即时显示预计保本价。")
                            .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                    }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(GoldTheme.up) }
                }.padding(16)
            }.background(GoldTheme.background)
                .safeAreaInset(edge: .bottom) {
                    Button(editing == nil ? "保存持仓" : "保存修改") { save() }
                        .buttonStyle(GoldPrimaryButtonStyle()).padding(16).background(GoldTheme.background)
                }
                .navigationTitle(editing == nil ? "记一笔黄金" : "编辑持仓").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.foregroundStyle(GoldTheme.textSecondary) } }
        }.presentationBackground(GoldTheme.background)
            .task(id: purchasePrice.selectedDay) { await purchasePrice.load(); draft.priceText = purchasePrice.priceText }
            .onChange(of: purchasePrice.priceText) { draft.priceText = purchasePrice.priceText }
    }

    private var priceReferenceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if purchasePrice.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在获取所选日期参考价…")
                }
            }
            if let reference = purchasePrice.reference {
                Text(referenceDescription(reference))
                if purchasePrice.isManual {
                    HStack {
                        Text("已手动填写，保存使用你的单价")
                        Spacer(minLength: 8)
                        Button("使用参考价") { purchasePrice.useReference() }
                            .foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                    }
                } else {
                    Text("参考价仅用于预填，可改为实际成交价")
                }
            }
            if let issue = purchasePrice.issue {
                HStack(alignment: .center, spacing: 8) {
                    Text(issueDescription(issue))
                    Spacer(minLength: 0)
                    if issue != .missingDay {
                        Button("重试") { Task { await purchasePrice.load() } }
                            .foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                            .disabled(purchasePrice.isLoading)
                    }
                }
            }
        }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
    }
    private func referenceDescription(_ reference: HoldingPurchasePriceReference) -> String {
        if !reference.isHistorical { return "参考 · \(marketBasis.title)最新可用金价 \(reference.price.moneyText) 元/克" }
        let day = HoldingsSelection.dateText(reference.date)
        if let fx = reference.exchangeRate {
            return "参考 · \(day)国际收盘价，按最新可用汇率 \(fx.formatted(.number.precision(.fractionLength(2...4)))) 折算为 \(reference.price.moneyText) 元/克（非历史人民币成交价）"
        }
        return "参考 · \(day)国内收盘价 \(reference.price.moneyText) 元/克"
    }
    private func issueDescription(_ issue: HoldingPurchasePriceModel.Issue) -> String {
        switch issue {
        case .missingDay: "当天没有日线报价，请填写实际购入单价"
        case .missingExchangeRate: "汇率暂不可用，请填写实际购入单价"
        case .unavailable: "参考价暂未获取成功，可手动填写购入单价"
        }
    }

    private func save() {
        guard let input = draft.input, GoldReturnCalculator.calculate(input, referencePrice: nil) != nil else {
            errorMessage = "请检查克重、价格、纯度和费用，折价应小于100%。"; return
        }
        guard timestamp <= .now else { errorMessage = "购买日期不能晚于当前时间"; return }
        if let editing, editing.disposition != "holding" { errorMessage = "这笔黄金已处置，无法编辑。"; return }
        let record = editing ?? HoldingRecord(grams: input.grams, unitPriceCNY: input.unitPrice, timestamp: timestamp)
        draft.apply(to: record, input: input)
        record.timestamp = timestamp
        if editing != nil { record.resetAlertBaselines() }
        if editing == nil { record.bookName = targetBook ?? book; modelContext.insert(record) }
        do { try modelContext.save() } catch {
            modelContext.rollback(); errorMessage = "保存失败，请重试。"; return
        }
        onSaved?()
        dismiss()
    }
}

// MARK: - 金额格式化

extension Double {
    /// 925.93
    var moneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)))
    }

    /// +24.98 / −12.30
    var signedMoneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)).sign(strategy: .always()))
    }
}
