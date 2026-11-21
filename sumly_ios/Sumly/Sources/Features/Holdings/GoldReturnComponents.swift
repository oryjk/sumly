import SwiftUI
import UIKit

extension View {
    /// 统一为含数字键盘的表单添加交互式下滑收起和键盘顶部「完成」按钮。
    func goldKeyboardDismissable() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                }
            }
    }
}

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

