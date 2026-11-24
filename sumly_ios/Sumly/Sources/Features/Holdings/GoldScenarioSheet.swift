import SwiftUI

struct GoldScenarioSheet: View {
    let record: HoldingRecord
    let referencePrice: Double?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("holdings.hideAmounts") private var hidden = false
    @State private var priceText: String
    private let upper: Double
    init(record: HoldingRecord, referencePrice: Double?) {
        self.record = record; self.referencePrice = referencePrice
        let breakEven = GoldReturnCalculator.calculate(record.returnInput, referencePrice: nil)?.breakEvenPrice ?? 1000
        let price = referencePrice ?? breakEven
        _priceText = State(initialValue: price.moneyText)
        upper = max(1000, price * 1.5, breakEven * 1.2)
    }
    private var price: Double? { GoldReturnCalculator.validPrice(Double(priceText)) }
    private var result: GoldReturnResult? { GoldReturnCalculator.calculate(record.returnInput, referencePrice: price) }
    private enum QuickOption: String, CaseIterable, Identifiable {
        case down10 = "-10%"
        case down5 = "-5%"
        case current = "current"
        case breakEven = "breakEven"
        case up5 = "+5%"
        case up10 = "+10%"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .current: L10n.tr("当前")
            case .breakEven: L10n.tr("保本")
            default: rawValue
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr("如果参考金价变成这个价格，这笔黄金会怎样？")).font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    GoldInputField(title: L10n.tr("假设参考金价（元/克）"), text: $priceText)
                    Slider(value: Binding(get: { min(max(price ?? 1, 1), upper) }, set: { priceText = $0.moneyText }), in: 1...upper)
                        .tint(GoldTheme.gold).accessibilityLabel(L10n.tr("假设参考金价"))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(QuickOption.allCases) { option in
                            Button(option.label) { choose(option) }.buttonStyle(GoldCapsuleStyle())
                                .disabled(option != .breakEven && referencePrice == nil)
                        }
                    }
                    GoldResultMetric(title: L10n.tr("现在卖预计到手 · 情景估算"), value: GoldReturnPresentation.money(result?.proceeds, hidden: hidden), color: GoldTheme.gold)
                    GoldResultMetric(title: L10n.tr("真实盈亏"), value: GoldReturnPresentation.money(result?.profit, hidden: hidden, signed: true), color: (result?.profit ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                    GoldResultMetric(title: L10n.tr("真实收益率"), value: GoldReturnPresentation.percent(result?.profitPercent, hidden: hidden))
                    Text(GoldReturnPresentation.status(price: price, breakEven: result?.breakEvenPrice, hidden: hidden)).font(.subheadline).foregroundStyle(GoldTheme.gold)
                    Text(L10n.tr("情景计算使用这笔持仓的纯度和回收规则，不改变实际持仓，也不预测未来金价。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }.padding(16)
            }.background(GoldTheme.background)
                .goldKeyboardDismissable()
                .navigationTitle(L10n.tr("情景测算")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
    }
    private func choose(_ option: QuickOption) {
        if option == .breakEven, let value = result?.breakEvenPrice { priceText = value.moneyText; return }
        guard let current = referencePrice else { return }
        let factor: Double
        switch option { case .down10: factor = 0.9; case .down5: factor = 0.95; case .up5: factor = 1.05; case .up10: factor = 1.1; default: factor = 1 }
        priceText = (current * factor).moneyText
    }
}
