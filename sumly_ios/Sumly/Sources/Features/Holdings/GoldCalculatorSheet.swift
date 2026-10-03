import SwiftUI

struct GoldCalculatorSheet: View {
    let model: HoldingsViewModel
    let marketBasis: GoldMarketBasis
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HoldingDraft
    @State private var rules = false
    @State private var saving = false
    @State private var saved = false
    @AppStorage("holdings.hideAmounts") private var hidden = false

    init(model: HoldingsViewModel, marketBasis: GoldMarketBasis) {
        self.model = model; self.marketBasis = marketBasis
        var draft = HoldingDraft()
        draft.priceText = model.quote.map { String($0.cnyPerGram) } ?? ""
        _draft = State(initialValue: draft)
    }
    private var result: GoldReturnResult? { draft.input.flatMap { GoldReturnCalculator.calculate($0, referencePrice: model.quote?.cnyPerGram) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("买之前，先算清这笔黄金的钱。").font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    Picker("黄金类型", selection: $draft.assetType) { ForEach(GoldAssetType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        GoldInputField(title: "克重（g）", text: $draft.gramsText, placeholder: "例如 30")
                        GoldInputField(title: "商家裸金报价（元/克）", text: $draft.priceText, placeholder: "实际报价")
                    }
                    Picker("工费方式", selection: $draft.laborPerGram) { Text("按克").tag(true); Text("总额").tag(false) }.pickerStyle(.segmented)
                    GoldInputField(title: draft.laborPerGram ? "工费（元/克）" : "工费总额（元）", text: $draft.laborText)
                    DisclosureGroup(isExpanded: $rules) {
                        VStack(spacing: 14) {
                            GoldInputField(title: "纯度（%）", text: $draft.purityText)
                            GoldInputField(title: "其他成本（元）", text: $draft.otherText)
                            GoldRecoveryFields(draft: $draft)
                        }.padding(.top, 12)
                    } label: {
                        Text(draft.input?.rule.isDefault == false ? "用户自定义回收估算 · 查看参数" : "当前使用 Sumly 默认回收估算")
                            .font(.caption).foregroundStyle(GoldTheme.gold)
                    }
                    if let result {
                        GoldResultMetric(title: "预计总支出", value: GoldReturnPresentation.money(result.totalCost, hidden: hidden), color: GoldTheme.gold)
                        HStack {
                            GoldResultMetric(title: "综合买入成本 / g", value: GoldReturnPresentation.money(result.comprehensiveUnitCost, hidden: hidden))
                            GoldResultMetric(title: "当前买入溢价 / g", value: GoldReturnPresentation.money(result.premiumPerGram, hidden: hidden, signed: true))
                        }
                        GoldResultMetric(title: "真实保本金价 / g", value: GoldReturnPresentation.money(result.breakEvenPrice, hidden: hidden), color: GoldTheme.gold)
                        Text(hidden ? "回本所需涨幅 ••••" : result.requiredRisePercent.map { $0 > 0 ? "当前参考价还需上涨约 \($0.moneyText)%" : "当前参考价已达到预计保本线" } ?? "暂无参考金价，保本价仍可计算")
                            .font(.subheadline).foregroundStyle(GoldTheme.text)
                    } else { Text("填写有效克重与报价，结果立即更新。") .font(.footnote).foregroundStyle(GoldTheme.textSecondary) }
                    Text(GoldReturnPresentation.quoteStatus(model.quote, basis: marketBasis, failed: model.quoteFailed)).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    Text("以上为估算，不代表渠道报价或购买建议。") .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }.padding(16)
            }.background(GoldTheme.background)
                .safeAreaInset(edge: .bottom) {
                    Button("保存为持仓") { saving = true }.buttonStyle(GoldPrimaryButtonStyle())
                        .disabled(result == nil).opacity(result == nil ? 0.5 : 1).padding(16).background(GoldTheme.background)
                }
                .navigationTitle("买前算一算").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
            .sheet(isPresented: $saving, onDismiss: { if saved { dismiss() } }) {
                AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, marketBasis: marketBasis, seed: draft, onSaved: { saved = true })
            }
    }
}
