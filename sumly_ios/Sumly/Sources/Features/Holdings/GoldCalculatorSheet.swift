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
                    Text(L10n.tr("买之前，先算清这笔黄金的钱。")).font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    Picker(L10n.tr("黄金类型"), selection: $draft.assetType) { ForEach(GoldAssetType.allCases) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        GoldInputField(title: L10n.tr("克重（g）"), text: $draft.gramsText, placeholder: L10n.tr("例如 30"))
                        GoldInputField(title: L10n.tr("商家裸金报价（元/克）"), text: $draft.priceText, placeholder: L10n.tr("实际报价"))
                    }
                    Picker(L10n.tr("工费方式"), selection: $draft.laborPerGram) { Text(L10n.tr("按克")).tag(true); Text(L10n.tr("总额")).tag(false) }.pickerStyle(.segmented)
                    GoldInputField(title: draft.laborPerGram ? L10n.tr("工费（元/克）") : L10n.tr("工费总额（元）"), text: $draft.laborText)
                    DisclosureGroup(isExpanded: $rules) {
                        VStack(spacing: 14) {
                            GoldInputField(title: L10n.tr("纯度（%）"), text: $draft.purityText)
                            GoldInputField(title: L10n.tr("其他成本（元）"), text: $draft.otherText)
                            GoldRecoveryFields(draft: $draft)
                        }.padding(.top, 12)
                    } label: {
                        Text(draft.input?.rule.isDefault == false ? L10n.tr("用户自定义回收估算 · 查看参数") : L10n.tr("当前使用 Sumly 默认回收估算"))
                            .font(.caption).foregroundStyle(GoldTheme.gold)
                    }
                    if let result {
                        GoldResultMetric(title: L10n.tr("预计总支出"), value: GoldReturnPresentation.money(result.totalCost, hidden: hidden), color: GoldTheme.gold)
                        HStack {
                            GoldResultMetric(title: L10n.tr("综合买入成本 / g"), value: GoldReturnPresentation.money(result.comprehensiveUnitCost, hidden: hidden))
                            GoldResultMetric(title: L10n.tr("当前买入溢价 / g"), value: GoldReturnPresentation.money(result.premiumPerGram, hidden: hidden, signed: true))
                        }
                        GoldResultMetric(title: L10n.tr("真实保本金价 / g"), value: GoldReturnPresentation.money(result.breakEvenPrice, hidden: hidden), color: GoldTheme.gold)
                        Text(hidden ? L10n.tr("回本所需涨幅 ••••") : result.requiredRisePercent.map { $0 > 0 ? L10n.fmt("当前参考价还需上涨约 %@%%", $0.moneyText) : L10n.tr("当前参考价已达到预计保本线") } ?? L10n.tr("暂无参考金价，保本价仍可计算"))
                            .font(.subheadline).foregroundStyle(GoldTheme.text)
                    } else { Text(L10n.tr("填写有效克重与报价，结果立即更新。")) .font(.footnote).foregroundStyle(GoldTheme.textSecondary) }
                    Text(GoldReturnPresentation.quoteStatus(model.quote, basis: marketBasis, failed: model.quoteFailed)).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    Text(L10n.tr("以上为估算，不代表渠道报价或购买建议。")) .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }.padding(16)
            }.background(GoldTheme.background)
                .goldKeyboardDismissable(showToolbar: false)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    GoldKeyboardActionBar {
                        Button(L10n.tr("保存为持仓")) { saving = true }
                            .buttonStyle(GoldPrimaryButtonStyle())
                            .disabled(result == nil)
                            .opacity(result == nil ? 0.5 : 1)
                    }
                }
                .navigationTitle(L10n.tr("买前算一算")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("关闭")) { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
            .sheet(isPresented: $saving, onDismiss: { if saved { dismiss() } }) {
                AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, marketBasis: marketBasis, seed: draft, onSaved: { saved = true })
            }
    }
}
