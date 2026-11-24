import Foundation

enum GoldAssetType: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case bean = "金豆"
    case bar = "金条"
    case jewelry = "金饰"
    case accumulation = "积存金"
    case other = "其他"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bean: L10n.tr("金豆")
        case .bar: L10n.tr("金条")
        case .jewelry: L10n.tr("金饰")
        case .accumulation: L10n.tr("积存金")
        case .other: L10n.tr("其他")
        }
    }

    /// 3 秒极简入库首屏展示的 4 大核心黄金形态。
    static let primaryQuickTypes: [GoldAssetType] = [.bean, .bar, .jewelry, .accumulation]

    /// 切换形态时自动建议的默认纯度（%）。
    var defaultPurityText: String {
        switch self {
        case .jewelry: "99.9"
        case .bean, .bar, .accumulation, .other: "99.99"
        }
    }

    /// 切换形态时自动建议的默认按克工费（元/克）。
    var defaultLaborPerGramText: String {
        switch self {
        case .bean: "10"
        case .bar: "10"
        case .jewelry: "50"
        case .accumulation: "0"
        case .other: ""
        }
    }

    /// 形态卡片上的简短特征标签。
    var quickTagline: String {
        switch self {
        case .bean: "99.99%"
        case .bar: "99.99%"
        case .jewelry: "99.9%"
        case .accumulation: L10n.tr("0工费")
        case .other: L10n.tr("自定义")
        }
    }

    /// 攒金盒陈列计数单位。
    var displayUnit: String {
        switch self {
        case .bean: L10n.tr("颗")
        case .bar: L10n.tr("根")
        case .jewelry: L10n.tr("件")
        case .accumulation, .other: L10n.tr("笔")
        }
    }
}
enum HoldingCostMode: String, CaseIterable, Identifiable, Sendable {
    case total = "购买总价", unit = "购买单价"
    var id: String { rawValue }
    var localizedTitle: String {
        switch self {
        case .total: L10n.tr("购买总价")
        case .unit: L10n.tr("购买单价")
        }
    }
}

/// 新增、编辑、买前计算共享表单草稿；非法中间输入不参与计算。
struct HoldingDraft: Sendable {
    static let quickGramOptions: [Double] = [1, 5, 10, 20, 50, 100]

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

    var parsedGrams: Double? {
        guard let value = number(gramsText), value > 0, value <= 1_000_000 else { return nil }
        return value
    }

    var parsedUnitPrice: Double? {
        guard let value = number(priceText), value > 0, value <= 1_000_000 else { return nil }
        return value
    }

    /// 切换黄金形态：按形态应用合理默认纯度与按克工费，绝不覆盖用户已输入的克重、单价、总价或备注。
    mutating func selectAssetType(_ newType: GoldAssetType, applyDefaults: Bool = true) {
        assetType = newType
        guard applyDefaults else { return }
        purityText = newType.defaultPurityText
        laborPerGram = true
        laborText = newType.defaultLaborPerGramText
        if costMode == .unit {
            syncCalculatedTotal()
        }
    }

    /// 一键选择快捷克重胶囊：写入克重并基于单价/参考价实时联动估算总价。
    mutating func applyQuickGrams(_ grams: Double, fallbackUnitPrice: Double? = nil) {
        guard grams.isFinite, grams > 0, grams <= 1_000_000 else { return }
        gramsText = Self.formatGrams(grams)
        if parsedUnitPrice == nil, let fallbackUnitPrice, fallbackUnitPrice.isFinite, fallbackUnitPrice > 0 {
            priceText = Self.formatMoney(fallbackUnitPrice)
        }
        if costMode == .unit {
            syncCalculatedTotal()
        }
    }

    /// 手动更新克重文本；在单价模式下同步刷新估算总价。
    mutating func updateGrams(_ text: String) {
        gramsText = text
        if costMode == .unit {
            syncCalculatedTotal()
        }
    }

    /// 更新裸金单价并切换为单价联动模式，实时重算参考总价。
    mutating func updateUnitPrice(_ text: String) {
        priceText = text
        costMode = .unit
        syncCalculatedTotal()
    }

    /// 直接填写实际支付总价，切换为总价优先模式（不重复叠加默认工费）。
    mutating func updateTotalPrice(_ text: String) {
        totalText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            costMode = .unit
        } else {
            costMode = .total
        }
    }

    /// 在单价模式下按当前克重、单价与工费/其他成本同步估算总价文本。
    mutating func syncCalculatedTotal() {
        guard costMode == .unit else { return }
        guard let calculated = input?.totalCost, calculated.isFinite, calculated > 0 else {
            totalText = ""
            return
        }
        totalText = Self.formatMoney(calculated)
    }

    /// 纯度与工费简要摘要，供极简入库页折叠状态展示。
    var defaultsSummaryText: String {
        let purity = purityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let purityLabel = purity.isEmpty ? "99.99%" : "\(purity)%"
        let laborValue = number(laborText, optional: true) ?? 0
        if laborValue <= 0 {
            let discountValue = number(discountText, optional: true) ?? 0
            if assetType == .accumulation && discountValue > 0 {
                return L10n.fmt("%@ · 赎回%@%%", purityLabel, Self.formatGrams(discountValue))
            }
            return L10n.fmt("%@ · 0工费", purityLabel)
        }
        let formattedLabor = Self.formatGrams(laborValue)
        return laborPerGram
            ? L10n.fmt("%@ · 工费¥%@/g", purityLabel, formattedLabor)
            : L10n.fmt("%@ · 工费¥%@", purityLabel, formattedLabor)
    }

    static func formatGrams(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    static func formatPrecise(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...4)))
    }

    static func formatMoney(_ value: Double) -> String {
        String(format: "%.2f", value)
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
        gramsText = Self.formatPrecise(record.grams)
        priceText = Self.formatPrecise(record.unitPriceCNY)
        if let total = record.purchaseTotalOverride {
            costMode = .total
            totalText = Self.formatPrecise(total)
        }
        laborText = record.laborFee > 0 ? Self.formatPrecise(record.laborFee) : ""
        laborPerGram = false
        otherText = record.extraFee > 0 ? Self.formatPrecise(record.extraFee) : ""
        purityText = Self.formatPrecise(record.purity * 100)
        brand = record.brand; channel = record.purchaseChannel; note = record.note
        deductionText = record.recoveryDeduction > 0 ? Self.formatPrecise(record.recoveryDeduction) : ""
        discountText = record.recoveryDiscount > 0 ? Self.formatPrecise(record.recoveryDiscount * 100) : ""
        fixedFeeText = record.recoveryFixedFee > 0 ? Self.formatPrecise(record.recoveryFixedFee) : ""
        if costMode == .unit {
            syncCalculatedTotal()
        }
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
