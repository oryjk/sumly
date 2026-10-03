import Foundation

/// 所有页面共用的回收参数。折价为扣减后再折扣的比例，而非保留比例。
struct GoldRecoveryRule: Equatable, Codable, Sendable {
    var perGramDeduction: Double = 0
    var discountRate: Double = 0
    var fixedFee: Double = 0
    var isDefault: Bool { perGramDeduction == 0 && discountRate == 0 && fixedFee == 0 }
    var isValid: Bool {
        perGramDeduction.isFinite && perGramDeduction >= 0 && discountRate.isFinite &&
        discountRate >= 0 && discountRate < 1 && fixedFee.isFinite && fixedFee >= 0
    }
}

struct GoldReturnInput: Equatable, Sendable {
    var grams: Double
    var purity: Double = 1
    var unitPrice: Double
    /// 总额，表单负责把按克工费转换成总额。
    var laborFee: Double = 0
    var otherCost: Double = 0
    /// 已支付总额是最终成本，工费和其他成本不再次相加。
    var totalCostOverride: Double? = nil
    var rule: GoldRecoveryRule = .init()
    var totalCost: Double { totalCostOverride ?? (grams * unitPrice + laborFee + otherCost) }
    var effectiveGrams: Double { grams * purity }
    var isValid: Bool {
        grams.isFinite && grams > 0 && purity.isFinite && purity > 0 && purity <= 1 &&
        unitPrice.isFinite && unitPrice >= 0 && laborFee.isFinite && laborFee >= 0 &&
        otherCost.isFinite && otherCost >= 0 && totalCost.isFinite && totalCost >= 0 &&
        effectiveGrams.isFinite && effectiveGrams > 0 && rule.isValid
    }
}

struct GoldReturnResult: Equatable, Sendable {
    var totalCost: Double
    var effectiveGrams: Double
    var bookValue: Double?
    var recoveryUnitPrice: Double?
    var proceeds: Double?
    var profit: Double?
    var profitPercent: Double?
    var breakEvenPrice: Double
    var priceDistance: Double?
    var requiredRisePercent: Double?
    var comprehensiveUnitCost: Double
    var premiumPerGram: Double?
}

struct GoldPortfolioReturn: Equatable, Sendable {
    var grams: Double
    var totalCost: Double
    var bookValue: Double?
    var proceeds: Double?
    var profit: Double?
    var profitPercent: Double?
    var breakEvenPrice: Double?
    var todayChange: Double?
}

/// 不依赖 SwiftUI/SwiftData；情景、保本反推和提醒均使用此内核。
enum GoldReturnCalculator {
    static func validPrice(_ price: Double?) -> Double? {
        guard let price, price.isFinite, price > 0 else { return nil }
        return price
    }

    /// 提醒目标与保本反推共享同一反函数；目标到手为0时，价格0即满足下限。
    static func referencePrice(_ input: GoldReturnInput, targetProceeds: Double) -> Double? {
        guard input.isValid, targetProceeds.isFinite, targetProceeds >= 0 else { return nil }
        if targetProceeds == 0 { return 0 }
        let price = (targetProceeds + input.rule.fixedFee) / (input.effectiveGrams * (1 - input.rule.discountRate)) + input.rule.perGramDeduction
        return price.isFinite ? price : nil
    }

    static func calculate(_ input: GoldReturnInput, referencePrice: Double?) -> GoldReturnResult? {
        guard input.isValid else { return nil }
        let cost = input.totalCost
        let weight = input.effectiveGrams
        let rule = input.rule
        guard let breakEven = Self.referencePrice(input, targetProceeds: cost) else { return nil }
        let price = validPrice(referencePrice)
        let bookValue = price.map { $0 * weight }
        let unit = price.map { max(0, $0 - rule.perGramDeduction) * (1 - rule.discountRate) }
        let proceeds = unit.map { max(0, $0 * weight - rule.fixedFee) }
        if let proceeds, !proceeds.isFinite { return nil }
        if let bookValue, !bookValue.isFinite { return nil }
        let profit = proceeds.map { $0 - cost }
        let percent = cost > 0 ? profit.map { $0 / cost * 100 } : nil
        let distance = price.map { $0 - breakEven }
        let rise = price.map { max(0, breakEven / $0 - 1) * 100 }
        let unitCost = cost / input.grams
        let premium = price.map { unitCost - $0 }
        guard [percent, distance, rise, premium, unitCost].compactMap({ $0 }).allSatisfy(\.isFinite) else { return nil }
        return .init(totalCost: cost, effectiveGrams: weight, bookValue: bookValue, recoveryUnitPrice: unit,
                     proceeds: proceeds, profit: profit, profitPercent: percent,
                     breakEvenPrice: breakEven, priceDistance: distance,
                     requiredRisePercent: rise, comprehensiveUnitCost: unitCost, premiumPerGram: premium)
    }

    static func aggregate(_ inputs: [GoldReturnInput], referencePrice: Double?, previousPrice: Double? = nil) -> GoldPortfolioReturn? {
        guard inputs.allSatisfy(\.isValid) else { return nil }
        let results = inputs.compactMap { calculate($0, referencePrice: referencePrice) }
        guard results.count == inputs.count else { return nil }
        let cost = results.reduce(0) { $0 + $1.totalCost }
        let grams = inputs.reduce(0) { $0 + $1.grams }
        guard cost.isFinite && grams.isFinite else { return nil }
        let hasQuote = validPrice(referencePrice) != nil && !inputs.isEmpty
        let proceeds = hasQuote ? results.reduce(0) { $0 + ($1.proceeds ?? 0) } : nil
        let value = hasQuote ? results.reduce(0) { $0 + ($1.bookValue ?? 0) } : nil
        let profit = proceeds.map { $0 - cost }
        // 每笔到手含0下限，异质规则不能只取单笔保本均值。
        var breakEven: Double?
        if !inputs.isEmpty {
            var low = 0.0
            var high = results.map(\.breakEvenPrice).max() ?? 0
            for _ in 0..<80 {
                let middle = low + (high - low) / 2
                let total = inputs.reduce(0) { $0 + (calculate($1, referencePrice: middle)?.proceeds ?? 0) }
                if total >= cost { high = middle } else { low = middle }
            }
            breakEven = high
        }
        let previous = validPrice(previousPrice).flatMap { price -> Double? in
            guard hasQuote else { return nil }
            return inputs.reduce(0) { $0 + (calculate($1, referencePrice: price)?.proceeds ?? 0) }
        }
        let percent = cost > 0 ? profit.map { $0 / cost * 100 } : nil
        let change = proceeds.flatMap { current in previous.map { current - $0 } }
        guard [proceeds, value, profit, percent, change].compactMap({ $0 }).allSatisfy(\.isFinite) else { return nil }
        return .init(grams: grams, totalCost: cost, bookValue: value, proceeds: proceeds, profit: profit,
                     profitPercent: percent, breakEvenPrice: breakEven, todayChange: change)
    }
}
