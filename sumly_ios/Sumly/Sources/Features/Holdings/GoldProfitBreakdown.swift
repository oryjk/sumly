import Foundation

/// Attribution is derived from the same payout kernel. Manual totals deliberately
/// remain combined: their unit price may have been inferred by the entry form.
struct GoldProfitBreakdown: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case price, purity, labor, other, unitemized, deduction, discount, fixed, sale
        var title: String {
            switch self {
            case .price: "金价变化"
            case .purity: "纯度折算"
            case .labor: "购入工费"
            case .other: "其他购入成本"
            case .unitemized: "金值与总投入差额"
            case .deduction: "每克回收扣减"
            case .discount: "回收比例折价"
            case .fixed: "固定卖出费用"
            case .sale: "实际到手与总投入差额"
            }
        }
        var explanation: String {
            switch self {
            case .price: "当前参考金价与录入的裸金单价之差，按购入克重计算；不代表今天一天的涨跌。"
            case .purity: "按录入纯度折算有效含金量。它是估值调整，不是一笔额外收费。"
            case .labor: "购入时支付的工费已计入总投入，回收估值不包含这部分工费。"
            case .other: "购入时录入的其他成本已计入总投入。"
            case .unitemized: "这部分记录以手动总价为准。只比较当前含金价值与总投入，不推断其中的裸金价格、工费或其他成本。"
            case .deduction: "按有效克重扣减，扣减后的金价最低为零。"
            case .discount: "先扣除每克回收扣减，再按录入比例折价。"
            case .fixed: "从折价后的金额扣除固定费用；预计到手最低为零，因此此处显示实际影响金额。组合按每笔独立卖出估算。"
            case .sale: "仅用已记录的实际卖出到手金额减去总投入。未记录成交明细，不能拆分金价与回收费用的贡献。"
            }
        }
    }
    /// Index refers to the exact input array, so duplicate names/dates remain distinct.
    struct Contribution: Equatable, Identifiable, Sendable {
        let recordIndex: Int
        let cents: Int64
        var id: Int { recordIndex }
    }
    struct Component: Equatable, Identifiable, Sendable {
        let kind: Kind
        let cents: Int64
        var contributions: [Contribution] = []
        var id: Kind { kind }
        var amount: Double { Double(cents) / 100 }
    }
    enum Direction: String, CaseIterable, Sendable {
        case increase, decrease, unchanged
        var title: String {
            switch self {
            case .increase: "收益从哪里来"
            case .decrease: "哪些因素拉低收益"
            case .unchanged: "无盈亏影响"
            }
        }
    }
    struct Group: Identifiable, Equatable, Sendable {
        let direction: Direction
        let components: [Component]
        var id: Direction { direction }
        // Decimal preserves cent totals even when large opposing effects cancel.
        var totalCents: Decimal { components.reduce(Decimal(0)) { $0 + Decimal($1.cents) } }
    }
    let components: [Component]
    let profitCents: Int64
    let totalCost: Double
    let goldValue: Double?
    let proceeds: Double
    let hasUnitemizedCost: Bool
    let hasUnconfiguredRecovery: Bool
    var profit: Double { Double(profitCents) / 100 }
    var groups: [Group] {
        Direction.allCases.compactMap { direction in
            let items = components.filter { item in
                switch direction {
                case .increase: item.cents > 0
                case .decrease: item.cents < 0
                case .unchanged: item.cents == 0
                }
            }
            return items.isEmpty ? nil : Group(direction: direction, components: items)
        }
    }
    func amount(for kind: Kind) -> Double { components.first { $0.kind == kind }?.amount ?? 0 }

    private static func cents(_ value: Double) -> Int64? {
        guard value.isFinite else { return nil }
        // Match moneyText's Foundation decimal rounding, including half cents.
        // A fixed locale gives ASCII digits; parsing also checks Int64 bounds.
        let displayed = value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.fractionLength(2)))
        return Int64(displayed.replacingOccurrences(of: ".", with: ""))
    }

    static func estimate(_ inputs: [GoldReturnInput], referencePrice: Double?) -> Self? {
        guard !inputs.isEmpty, let price = GoldReturnCalculator.validPrice(referencePrice),
              let aggregate = GoldReturnCalculator.aggregate(inputs, referencePrice: price),
              let profit = aggregate.profit, let target = cents(profit), let proceeds = aggregate.proceeds else { return nil }
        var values: [Kind: Double] = [:]
        var sources: [Kind: [(recordIndex: Int, value: Double)]] = [:]
        var unitemized = false
        func append(_ kind: Kind, _ value: Double, _ recordIndex: Int) {
            values[kind, default: 0] += value
            sources[kind, default: []].append((recordIndex, value))
        }
        for (recordIndex, input) in inputs.enumerated() {
            guard let result = GoldReturnCalculator.calculate(input, referencePrice: price),
                  let goldValue = result.bookValue, let payout = result.proceeds else { return nil }
            let nominalValue = price * input.grams
            if input.totalCostOverride != nil || !nominalValue.isFinite {
                unitemized = true
                append(.unitemized, goldValue - input.totalCost, recordIndex)
            } else {
                append(.price, nominalValue - input.unitPrice * input.grams, recordIndex)
                append(.purity, goldValue - nominalValue, recordIndex)
                append(.labor, -input.laborFee, recordIndex)
                append(.other, -input.otherCost, recordIndex)
            }
            let deducted = max(0, price - input.rule.perGramDeduction) * input.effectiveGrams
            let discounted = deducted * (1 - input.rule.discountRate)
            append(.deduction, deducted - goldValue, recordIndex)
            append(.discount, discounted - deducted, recordIndex)
            append(.fixed, payout - discounted, recordIndex)
        }
        // Round cumulative boundaries, rather than each fee independently. This
        // preserves the displayed equality down to the cent, including portfolios.
        var kinds = Kind.allCases.filter { sources[$0]?.contains { $0.value != 0 } == true }
        if kinds.isEmpty { kinds = [unitemized ? .unitemized : .price] }
        var running = 0.0
        var previous: Int64 = 0
        var components: [Component] = []
        for (index, kind) in kinds.enumerated() {
            var recordRunning = running
            running += values[kind] ?? 0
            guard let boundary = index == kinds.count - 1 ? target : cents(running) else { return nil }
            let (delta, overflow) = boundary.subtractingReportingOverflow(previous)
            guard !overflow else { return nil }
            let allSources = sources[kind] ?? []
            let nonzero = allSources.filter { $0.value != 0 }
            let entries = nonzero.isEmpty ? allSources : nonzero
            var recordPrevious = previous
            var contributions: [Contribution] = []
            for (entryIndex, entry) in entries.enumerated() {
                recordRunning += entry.value
                // Share the component's cumulative boundaries, including its final
                // cent correction; independently rounding records would not add up.
                guard let recordBoundary = entryIndex == entries.count - 1 ? boundary : cents(recordRunning) else { return nil }
                let (recordDelta, recordOverflow) = recordBoundary.subtractingReportingOverflow(recordPrevious)
                guard !recordOverflow else { return nil }
                contributions.append(.init(recordIndex: entry.recordIndex, cents: recordDelta))
                recordPrevious = recordBoundary
            }
            components.append(.init(kind: kind, cents: delta, contributions: contributions))
            previous = boundary
        }
        return .init(components: components, profitCents: target, totalCost: aggregate.totalCost, goldValue: aggregate.bookValue, proceeds: proceeds,
                     hasUnitemizedCost: unitemized, hasUnconfiguredRecovery: inputs.contains { $0.rule.isDefault })
    }

    static func sale(totalCost: Double, proceeds: Double) -> Self? {
        guard totalCost.isFinite, totalCost >= 0, proceeds.isFinite, proceeds >= 0,
              let target = cents(proceeds - totalCost) else { return nil }
        return .init(components: [.init(kind: .sale, cents: target, contributions: [.init(recordIndex: 0, cents: target)])], profitCents: target,
                     totalCost: totalCost, goldValue: nil, proceeds: proceeds, hasUnitemizedCost: true, hasUnconfiguredRecovery: false)
    }
}
