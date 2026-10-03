import Foundation

enum GoldAssetType: String, CaseIterable, Identifiable, Sendable {
    case jewelry = "金饰", bar = "金条", accumulation = "积存金", other = "其他"
    var id: String { rawValue }
}
enum HoldingCostMode: String, CaseIterable, Identifiable { case total = "购买总价", unit = "购买单价"; var id: String { rawValue } }

/// 新增、编辑、买前计算共享表单草稿；非法中间输入不参与计算。
struct HoldingDraft {
    var assetType = GoldAssetType.bar
    var gramsText = ""
    var priceText = ""
    var totalText = ""
    var costMode = HoldingCostMode.unit
    var laborText = ""
    var laborPerGram = true
    var otherText = ""
    var purityText = "99.99"
    var channel = ""
    var brand = ""
    var note = ""
    var deductionText = ""
    var discountText = ""
    var fixedFeeText = ""

    private func number(_ text: String, optional: Bool = false) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && optional { return 0 }
        guard let value = Double(text), value.isFinite, value >= 0, value <= 1_000_000_000 else { return nil }
        return value
    }
    var input: GoldReturnInput? {
        guard let grams = number(gramsText), grams > 0, grams <= 1_000_000,
              let labor = number(laborText, optional: true), let other = number(otherText, optional: true),
              let purity = number(purityText), purity > 0, purity <= 100,
              let deduction = number(deductionText, optional: true), let discount = number(discountText, optional: true), discount < 100,
              let fixed = number(fixedFeeText, optional: true) else { return nil }
        let total: Double?
        let price: Double
        if costMode == .total {
            guard let value = number(totalText), value > 0 else { return nil }
            total = value
            // 保留已有裸金单价；仅知总价时以综合单价作为基础参考。
            price = number(priceText) ?? max(0, (value - (laborPerGram ? labor * grams : labor) - other) / grams)
        } else {
            guard let value = number(priceText), value > 0, value <= 1_000_000 else { return nil }
            price = value; total = nil
        }
        let input = GoldReturnInput(grams: grams, purity: purity / 100, unitPrice: price,
                                    laborFee: laborPerGram ? labor * grams : labor, otherCost: other,
                                    totalCostOverride: total,
                                    rule: .init(perGramDeduction: deduction, discountRate: discount / 100, fixedFee: fixed))
        return input.isValid ? input : nil
    }
    init() {}
    init(record: HoldingRecord) {
        assetType = GoldAssetType(rawValue: record.assetType) ?? .other
        gramsText = String(record.grams); priceText = String(record.unitPriceCNY)
        if let total = record.purchaseTotalOverride { costMode = .total; totalText = String(total) }
        laborText = String(record.laborFee); laborPerGram = false
        otherText = String(record.extraFee); purityText = String(record.purity * 100)
        brand = record.brand; channel = record.purchaseChannel; note = record.note
        deductionText = String(record.recoveryDeduction); discountText = String(record.recoveryDiscount * 100)
        fixedFeeText = String(record.recoveryFixedFee)
    }
    func apply(to record: HoldingRecord, input: GoldReturnInput) {
        record.grams = input.grams; record.unitPriceCNY = input.unitPrice
        record.assetType = assetType.rawValue; record.purity = input.purity
        record.laborFee = input.laborFee; record.extraFee = input.otherCost
        record.purchaseTotalOverride = input.totalCostOverride
        record.recoveryDeduction = input.rule.perGramDeduction
        record.recoveryDiscount = input.rule.discountRate; record.recoveryFixedFee = input.rule.fixedFee
        record.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        record.purchaseChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
