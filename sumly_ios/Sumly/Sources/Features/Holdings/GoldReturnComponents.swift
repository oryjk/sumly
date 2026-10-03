import SwiftUI

struct GoldInputField: View {
    let title: String
    @Binding var text: String
    var placeholder = "0"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            TextField(placeholder, text: $text).keyboardType(.decimalPad)
                .font(.body).foregroundStyle(GoldTheme.text)
                .padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        }
    }
}

struct GoldAdvancedFields: View {
    @Binding var draft: HoldingDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("工费方式").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                Picker("工费方式", selection: $draft.laborPerGram) {
                    Text("按克").tag(true); Text("总额").tag(false)
                }.pickerStyle(.segmented)
            }
            GoldInputField(title: draft.laborPerGram ? "工费（元/克）" : "工费总额（元）", text: $draft.laborText)
            GoldInputField(title: "纯度（%）· 9999 = 99.99%", text: $draft.purityText)
            GoldInputField(title: "其他成本（元）", text: $draft.otherText)
            TextField("品牌 / 名称（可选）", text: $draft.brand).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            TextField("购买渠道（可选）", text: $draft.channel).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            TextField("备注（可选）", text: $draft.note).padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            GoldRecoveryFields(draft: $draft)
        }.foregroundStyle(GoldTheme.text)
    }
}

struct GoldRecoveryFields: View {
    @Binding var draft: HoldingDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回收规则 · 当前参考金价为基准").font(.subheadline.bold()).foregroundStyle(GoldTheme.gold)
            GoldInputField(title: "每克回收扣减（元/有效克）", text: $draft.deductionText)
            GoldInputField(title: "比例折价（%）", text: $draft.discountText)
            GoldInputField(title: "固定卖出费用（元/次）", text: $draft.fixedFeeText)
            Text("留空或全部为 0 时，尚未计入回收费用。请按实际回收渠道填写，这不是渠道报价。")
                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }
    }
}

struct GoldResultMetric: View {
    let title: String
    let value: String
    var color = GoldTheme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Text(value).font(.system(.title3, design: .rounded).bold()).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).goldCard()
    }
}

enum GoldReturnPresentation {
    /// Source rows and their subtotals format the same exact integer cents.
    static func centsMoney(_ cents: Decimal?, hidden: Bool = false, signed: Bool = true) -> String {
        if hidden { return "••••" }
        guard let cents else { return "—" }
        let amount = cents / 100
        let magnitude = amount < 0 ? -amount : amount
        let text = magnitude.formatted(.number.grouping(.never).precision(.fractionLength(2)))
        return "¥" + (amount < 0 ? "-" : signed ? "+" : "") + text
    }
    static func money(_ amount: Double?, hidden: Bool = false, signed: Bool = false) -> String {
        if hidden { return "••••" }
        guard let amount else { return "—" }
        let displayed = signed && abs(amount).moneyText == 0.0.moneyText ? 0.0 : amount
        return "¥" + (signed ? displayed.signedMoneyText : displayed.moneyText)
    }
    static func percent(_ value: Double?, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        return value.map { $0.signedMoneyText + "%" } ?? "—"
    }
    static func status(price: Double?, breakEven: Double?, hidden: Bool) -> String {
        guard let price = GoldReturnCalculator.validPrice(price), let breakEven else { return "获取参考金价后显示保本距离" }
        if hidden { return "保本距离 •••• 元/克" }
        let distance = price - breakEven
        return distance >= 0 ? "已超过真实保本线 ¥\(distance.moneyText) / g" : "距离真实保本还差 ¥\((-distance).moneyText) / g"
    }
    static func quoteStatus(_ quote: GoldQuote?, basis: GoldMarketBasis, failed: Bool = false, now: Date = .now) -> String {
        guard let quote else { return "参考金价暂不可用，仍可录入和查看保本价" }
        let stale = failed || now.timeIntervalSince(quote.asOf) > 300 || quote.asOf > now.addingTimeInterval(60)
        let time = quote.asOf.formatted(date: .abbreviated, time: .standard)
        return "\(basis.title)参考 · \(stale ? "非实时 · " : "")\(time)"
    }
}

struct GoldCalculationSheet: View {
    let records: [HoldingRecord]
    let quote: GoldQuote?
    let basis: GoldMarketBasis
    var hideAmounts = false
    var quoteFailed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("参考与参数").font(.title3.bold()).foregroundStyle(GoldTheme.gold)
                    Text(GoldReturnPresentation.quoteStatus(quote, basis: basis, failed: quoteFailed))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    LabeledContent("当前参考金价", value: GoldReturnPresentation.money(quote?.cnyPerGram, hidden: hideAmounts) + " / g")
                    Text(basis == .domestic ? "上海黄金交易所 Au99.99 国内参考价" : "伦敦金按行情汇率折算人民币/克，非品牌零售价")
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(record.displayName).font(.headline)
                            let input = record.returnInput
                            LabeledContent("克重 / 纯度", value: hideAmounts ? "••••" : "\(input.grams.moneyText) g · \((input.purity * 100).moneyText)%")
                            LabeledContent("有效克重", value: hideAmounts ? "••••" : "\(input.effectiveGrams.formatted(.number.precision(.fractionLength(0...4)))) g")
                            LabeledContent(input.totalCostOverride == nil ? "裸金单价" : "录入 / 反推单价（不用于来源归因）", value: GoldReturnPresentation.money(input.unitPrice, hidden: hideAmounts) + " / g")
                            LabeledContent("工费 / 其他成本", value: GoldReturnPresentation.money(input.laborFee, hidden: hideAmounts) + " / " + GoldReturnPresentation.money(input.otherCost, hidden: hideAmounts))
                            LabeledContent(input.totalCostOverride == nil ? "总投入" : "总投入 · 手动", value: GoldReturnPresentation.money(input.totalCost, hidden: hideAmounts))
                            if input.totalCostOverride != nil { Text("手动总价是最终现金支出，不再额外叠加工费与其他成本。") }
                            LabeledContent("每克回收扣减", value: GoldReturnPresentation.money(input.rule.perGramDeduction, hidden: hideAmounts))
                            LabeledContent("比例折价", value: hideAmounts ? "••••" : "\((input.rule.discountRate * 100).moneyText)%")
                            LabeledContent("固定卖出费用", value: GoldReturnPresentation.money(input.rule.fixedFee, hidden: hideAmounts))
                            Text(input.rule.isDefault ? "尚未计入回收费用" : "当前使用用户自定义回收估算").foregroundStyle(GoldTheme.gold)
                            if let result = GoldReturnCalculator.calculate(input, referencePrice: quote?.cnyPerGram) {
                                LabeledContent("预计回收单价", value: GoldReturnPresentation.money(result.recoveryUnitPrice, hidden: hideAmounts) + " / g")
                                LabeledContent("现在卖预计到手", value: GoldReturnPresentation.money(result.proceeds, hidden: hideAmounts))
                                LabeledContent("真实盈亏", value: GoldReturnPresentation.money(result.profit, hidden: hideAmounts, signed: true))
                                LabeledContent("真实保本金价", value: GoldReturnPresentation.money(result.breakEvenPrice, hidden: hideAmounts) + " / g")
                            }
                        }.font(.caption).goldCard()
                    }
                    Text("怎么算的？").font(.headline)
                    Text("有效克重 = 克重 × 纯度\n总投入 = 裸金单价 × 克重 + 工费 + 其他成本（手动总价优先）\n预计回收单价 = max(参考金价 − 每克扣减, 0) × (1 − 比例折价)\n预计到手 = max(预计回收单价 × 有效克重 − 固定费用, 0)\n真实盈亏 = 预计到手 − 总投入\n真实收益率 = 真实盈亏 ÷ 总投入\n真实保本价 = (总投入 + 固定费用) ÷ [有效克重 × (1 − 折价)] + 每克扣减")
                        .font(.caption).lineSpacing(6).foregroundStyle(GoldTheme.textSecondary)
                    if records.count > 1 { Text("组合金额逐笔求和；组合保本价按各笔独立规则反推，并非保本价的简单平均。固定费用按每笔独立卖出估算。") .font(.caption).foregroundStyle(GoldTheme.textSecondary) }
                    Text("当前结果为估算，真实成交价可能因渠道、纯度、检测和手续费变化。")
                        .font(.footnote).foregroundStyle(GoldTheme.gold)
                }.padding(16).foregroundStyle(GoldTheme.text)
            }.background(GoldTheme.background).navigationTitle("怎么算的？").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationBackground(GoldTheme.background).presentationDragIndicator(.visible)
    }
}
