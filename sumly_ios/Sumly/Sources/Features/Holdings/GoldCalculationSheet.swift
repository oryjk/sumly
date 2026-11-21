import SwiftUI

// MARK: - 金额与数值格式化（独立于 GoldReturnPresentation，避免影响既有测试）

enum GoldCalculationFormatter {
    /// 使用固定 `en_US` Locale 确保 `,` 千分位与 `.` 小数点在任何系统区域下稳定输出。
    private static let groupingLocale = Locale(identifier: "en_US")

    /// 规范货币格式：负号在 ¥ 前，带千分位（如 `-¥67,633.78`、`+¥1,234.50`、`¥105,380.50`）。
    static func currency(_ amount: Double?, signed: Bool = false, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        guard let amount, amount.isFinite else { return "—" }
        let absText = abs(amount).formatted(
            .number
                .locale(groupingLocale)
                .grouping(.automatic)
                .precision(.fractionLength(2))
        )
        if absText == "0.00" {
            return "¥0.00"
        }
        if amount < 0 {
            return "-¥" + absText
        }
        return (signed ? "+¥" : "¥") + absText
    }

    /// 克价格式（如 `¥755.01/g`、`+¥200.21/g`）。
    static func unitPrice(_ amount: Double?, signed: Bool = false, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        guard let amount, amount.isFinite else { return "—" }
        return currency(amount, signed: signed) + "/g"
    }

    /// 克重格式（如 `50.00 g` 或 `49.995 g`）。
    static func grams(_ value: Double?, maxFractionDigits: Int = 2, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        guard let value, value.isFinite else { return "—" }
        let text: String
        if maxFractionDigits <= 2 {
            text = value.formatted(
                .number
                    .locale(groupingLocale)
                    .grouping(.automatic)
                    .precision(.fractionLength(2))
            )
        } else {
            text = value.formatted(
                .number
                    .locale(groupingLocale)
                    .grouping(.automatic)
                    .precision(.fractionLength(0...maxFractionDigits))
            )
        }
        return text + " g"
    }

    /// 百分比格式（如 `-64.18%`、`+12.34%`、`99.99%`）。
    static func percent(_ value: Double?, signed: Bool = false, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        guard let value, value.isFinite else { return "—" }
        let absText = abs(value).formatted(
            .number
                .locale(groupingLocale)
                .grouping(.never)
                .precision(.fractionLength(2))
        )
        if absText == "0.00" {
            return "0.00%"
        }
        if value < 0 {
            return "-" + absText + "%"
        }
        return (signed ? "+" : "") + absText + "%"
    }

    /// 占比格式（如 `90.5%`）。
    static func sharePercent(_ ratio: Double, hidden: Bool = false) -> String {
        if hidden { return "••••" }
        guard ratio.isFinite else { return "—" }
        let clamped = max(0, min(1, ratio)) * 100
        return clamped.formatted(
            .number
                .locale(groupingLocale)
                .grouping(.never)
                .precision(.fractionLength(1))
        ) + "%"
    }
}

// MARK: - 纯逻辑拆解模型（Sendable，独立可测）

struct GoldCalculationItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let input: GoldReturnInput

    init(id: String, title: String, input: GoldReturnInput) {
        self.id = id
        self.title = title
        self.input = input
    }

    init(record: HoldingRecord) {
        self.id = record.id.uuidString
        self.title = record.displayName
        self.input = record.returnInput
    }
}

enum GoldCalculationScope: Hashable, Sendable {
    case summary
    case item(String)
}

struct GoldCalculationBreakdown: Equatable, Sendable {
    enum ProfitState: Equatable, Sendable {
        case noQuote
        case profit
        case loss
        case breakEven
    }

    enum CostSegmentKind: String, Equatable, Sendable {
        case rawGold
        case fees
        case manualTotal

        var title: String {
            switch self {
            case .rawGold: "裸金成本"
            case .fees: "工费与其他"
            case .manualTotal: "手动总投入"
            }
        }
    }

    struct CostSegment: Identifiable, Equatable, Sendable {
        let kind: CostSegmentKind
        let amount: Double
        let share: Double
        var id: CostSegmentKind { kind }
    }

    enum LegendKind: String, Equatable, Sendable {
        case rawGold
        case fees
        case manualTotal
        case proceeds
        case loss
        case profitGain
        case profitLoss
    }

    struct LegendEntry: Identifiable, Equatable, Sendable {
        let kind: LegendKind
        let title: String
        let amountText: String
        let shareText: String?
        var id: LegendKind { kind }
    }

    let isSummary: Bool
    let recordCount: Int
    let title: String
    let singleInput: GoldReturnInput?
    let referencePrice: Double?

    // 投入与重量
    let totalGrams: Double
    let effectiveGrams: Double
    let rawGoldCost: Double
    let laborCost: Double
    let otherCost: Double
    let feesCost: Double
    let manualTotalCost: Double
    let totalCost: Double
    let isManualTotalOnly: Bool
    let hasManualTotalCost: Bool
    let costSegments: [CostSegment]

    // 估值、损耗与盈亏
    let nominalGoldValue: Double?
    let bookValue: Double?
    let recoveryUnitPrice: Double?
    let proceeds: Double?
    let purityLoss: Double?
    let recoveryLoss: Double?
    let totalLoss: Double?
    let hasVisibleLoss: Bool
    let profit: Double?
    let profitPercent: Double?
    let profitState: ProfitState

    // 柱图纵轴上限（左右柱共用）
    let barMaxValue: Double

    // 保本价构成尺
    let baseUnitPrice: Double
    let baseUnitPriceLabel: String
    let breakEvenPrice: Double
    let breakEvenDilution: Double
    let dilutionLabel: String
    let distanceFromBreakEven: Double?
    let requiredRisePercent: Double?
    let rulerMaxPrice: Double

    // 回收规则特征
    let allDefaultRecoveryRules: Bool
    let someCustomRecoveryRules: Bool
    let hasPurityDiscount: Bool

    static let visibleLossThreshold: Double = 0.01
    private static let zeroAmountThreshold: Double = 0.005

    static func make(
        items: [GoldCalculationItem],
        scope: GoldCalculationScope,
        referencePrice: Double?
    ) -> GoldCalculationBreakdown? {
        guard !items.isEmpty else { return nil }
        switch scope {
        case .summary:
            if items.count == 1, let only = items.first {
                return make(inputs: [only.input], title: only.title, referencePrice: referencePrice, isSummary: false)
            }
            return make(inputs: items.map(\.input), title: "全部汇总", referencePrice: referencePrice, isSummary: true)
        case .item(let targetID):
            guard let matched = items.first(where: { $0.id == targetID }) else {
                if items.count == 1, let only = items.first {
                    return make(inputs: [only.input], title: only.title, referencePrice: referencePrice, isSummary: false)
                }
                return make(inputs: items.map(\.input), title: "全部汇总", referencePrice: referencePrice, isSummary: true)
            }
            return make(inputs: [matched.input], title: matched.title, referencePrice: referencePrice, isSummary: false)
        }
    }

    static func make(
        inputs: [GoldReturnInput],
        title: String = "全部汇总",
        referencePrice: Double?,
        isSummary: Bool? = nil
    ) -> GoldCalculationBreakdown? {
        guard !inputs.isEmpty, inputs.allSatisfy(\.isValid) else { return nil }
        let validQuote = GoldReturnCalculator.validPrice(referencePrice)
        let resolvedSummary = isSummary ?? (inputs.count > 1)

        var totalGrams = 0.0
        var effectiveGrams = 0.0
        var rawGoldCost = 0.0
        var laborCost = 0.0
        var otherCost = 0.0
        var manualTotalCost = 0.0
        var hasManual = false
        var allManual = true
        var allDefaultRule = true
        var someCustomRule = false
        var hasPurityDiscount = false
        var weightedRecoveryNumerator = 0.0

        var singleResults: [GoldReturnResult] = []
        singleResults.reserveCapacity(inputs.count)

        for input in inputs {
            guard let res = GoldReturnCalculator.calculate(input, referencePrice: validQuote) else {
                return nil
            }
            singleResults.append(res)
            totalGrams += input.grams
            effectiveGrams += input.effectiveGrams
            if input.purity < 0.9999999 {
                hasPurityDiscount = true
            }
            if input.rule.isDefault {
                // unchanged
            } else {
                allDefaultRule = false
                someCustomRule = true
            }
            if input.totalCostOverride != nil {
                hasManual = true
                manualTotalCost += input.totalCost
            } else {
                allManual = false
                rawGoldCost += input.unitPrice * input.grams
                laborCost += input.laborFee
                otherCost += input.otherCost
            }
            if let unit = res.recoveryUnitPrice {
                weightedRecoveryNumerator += unit * input.effectiveGrams
            }
        }

        guard totalGrams > 0, effectiveGrams > 0 else { return nil }

        let totalCost: Double
        let bookValue: Double?
        let proceeds: Double?
        let profit: Double?
        let profitPercent: Double?
        let breakEvenPrice: Double

        if inputs.count == 1, let single = singleResults.first {
            totalCost = single.totalCost
            bookValue = single.bookValue
            proceeds = single.proceeds
            profit = single.profit
            profitPercent = single.profitPercent
            breakEvenPrice = single.breakEvenPrice
        } else {
            guard let agg = GoldReturnCalculator.aggregate(inputs, referencePrice: validQuote),
                  let aggBreakEven = agg.breakEvenPrice else {
                return nil
            }
            totalCost = agg.totalCost
            bookValue = agg.bookValue
            proceeds = agg.proceeds
            profit = agg.profit
            profitPercent = agg.profitPercent
            breakEvenPrice = aggBreakEven
        }

        let feesCost = laborCost + otherCost
        let nominalGoldValue = validQuote.map { $0 * totalGrams }
        let purityLoss: Double? = {
            guard let nominal = nominalGoldValue, let book = bookValue else { return nil }
            return max(0, nominal - book)
        }()
        let recoveryLoss: Double? = {
            guard let book = bookValue, let net = proceeds else { return nil }
            return max(0, book - net)
        }()
        let totalLoss: Double? = {
            guard let nominal = nominalGoldValue, let net = proceeds else { return nil }
            return max(0, nominal - net)
        }()
        let hasVisibleLoss = (totalLoss ?? 0) > Self.visibleLossThreshold

        let recoveryUnitPrice: Double? = {
            guard validQuote != nil else { return nil }
            if inputs.count == 1 {
                return singleResults.first?.recoveryUnitPrice
            }
            return weightedRecoveryNumerator / effectiveGrams
        }()

        let profitState: ProfitState = {
            guard let profit else { return .noQuote }
            if profit >= Self.zeroAmountThreshold { return .profit }
            if profit <= -Self.zeroAmountThreshold { return .loss }
            return .breakEven
        }()

        // 左柱投入构成（只保留非零段）
        var segments: [CostSegment] = []
        let safeTotalCost = totalCost > 0 ? totalCost : 1
        if allManual {
            segments.append(.init(kind: .manualTotal, amount: totalCost, share: 1))
        } else {
            if rawGoldCost > Self.zeroAmountThreshold {
                segments.append(.init(kind: .rawGold, amount: rawGoldCost, share: rawGoldCost / safeTotalCost))
            }
            if feesCost > Self.zeroAmountThreshold {
                segments.append(.init(kind: .fees, amount: feesCost, share: feesCost / safeTotalCost))
            }
            if manualTotalCost > Self.zeroAmountThreshold {
                segments.append(.init(kind: .manualTotal, amount: manualTotalCost, share: manualTotalCost / safeTotalCost))
            }
            if segments.isEmpty {
                segments.append(.init(kind: .rawGold, amount: totalCost, share: 1))
            }
        }

        // 左右柱共用纵轴上限：max(总投入, 预计到手 + 可见损耗)
        let rightStackTop = (proceeds ?? 0) + (hasVisibleLoss ? (totalLoss ?? 0) : 0)
        let barMaxValue = max(totalCost, rightStackTop, 1)

        // 保本价构成尺
        let baseUnitPrice: Double
        let baseUnitPriceLabel: String
        let dilutionLabel: String
        if hasManual {
            baseUnitPrice = totalCost / totalGrams
            baseUnitPriceLabel = allManual ? "买入均价（手动总价）" : "综合买入均价"
            dilutionLabel = "纯度/回收摊薄"
        } else {
            baseUnitPrice = rawGoldCost / totalGrams
            baseUnitPriceLabel = "裸金均价"
            dilutionLabel = "工费/纯度/回收摊薄"
        }

        let breakEvenDilution = max(0, breakEvenPrice - baseUnitPrice)
        let distanceFromBreakEven = validQuote.map { $0 - breakEvenPrice }
        let requiredRisePercent = validQuote.map { max(0, breakEvenPrice / $0 - 1) * 100 }
        let rulerMaxPrice = max(validQuote ?? 0, baseUnitPrice, breakEvenPrice, 1)

        return GoldCalculationBreakdown(
            isSummary: resolvedSummary,
            recordCount: inputs.count,
            title: title,
            singleInput: inputs.count == 1 ? inputs.first : nil,
            referencePrice: validQuote,
            totalGrams: totalGrams,
            effectiveGrams: effectiveGrams,
            rawGoldCost: rawGoldCost,
            laborCost: laborCost,
            otherCost: otherCost,
            feesCost: feesCost,
            manualTotalCost: manualTotalCost,
            totalCost: totalCost,
            isManualTotalOnly: allManual,
            hasManualTotalCost: hasManual,
            costSegments: segments,
            nominalGoldValue: nominalGoldValue,
            bookValue: bookValue,
            recoveryUnitPrice: recoveryUnitPrice,
            proceeds: proceeds,
            purityLoss: purityLoss,
            recoveryLoss: recoveryLoss,
            totalLoss: totalLoss,
            hasVisibleLoss: hasVisibleLoss,
            profit: profit,
            profitPercent: profitPercent,
            profitState: profitState,
            barMaxValue: barMaxValue,
            baseUnitPrice: baseUnitPrice,
            baseUnitPriceLabel: baseUnitPriceLabel,
            breakEvenPrice: breakEvenPrice,
            breakEvenDilution: breakEvenDilution,
            dilutionLabel: dilutionLabel,
            distanceFromBreakEven: distanceFromBreakEven,
            requiredRisePercent: requiredRisePercent,
            rulerMaxPrice: rulerMaxPrice,
            allDefaultRecoveryRules: allDefaultRule,
            someCustomRecoveryRules: someCustomRule,
            hasPurityDiscount: hasPurityDiscount
        )
    }

    // MARK: - 图例与大白话文案（统一处理隐私脱敏）

    func legendEntries(hidden: Bool) -> [LegendEntry] {
        var entries: [LegendEntry] = []
        for segment in costSegments {
            let legendKind: LegendKind = switch segment.kind {
            case .rawGold: .rawGold
            case .fees: .fees
            case .manualTotal: .manualTotal
            }
            entries.append(.init(
                kind: legendKind,
                title: segment.kind.title,
                amountText: GoldCalculationFormatter.currency(segment.amount, hidden: hidden),
                shareText: hidden ? nil : GoldCalculationFormatter.sharePercent(segment.share)
            ))
        }
        if let proceeds {
            entries.append(.init(
                kind: .proceeds,
                title: "预计到手",
                amountText: GoldCalculationFormatter.currency(proceeds, hidden: hidden),
                shareText: nil
            ))
        }
        if hasVisibleLoss, let totalLoss {
            entries.append(.init(
                kind: .loss,
                title: "纯度与回收损耗",
                amountText: GoldCalculationFormatter.currency(-totalLoss, hidden: hidden),
                shareText: nil
            ))
        }
        if let profit {
            switch profitState {
            case .profit:
                entries.append(.init(
                    kind: .profitGain,
                    title: hidden ? "真实盈亏" : "浮盈",
                    amountText: GoldCalculationFormatter.currency(profit, signed: true, hidden: hidden),
                    shareText: nil
                ))
            case .loss:
                entries.append(.init(
                    kind: .profitLoss,
                    title: hidden ? "真实盈亏" : "浮亏",
                    amountText: GoldCalculationFormatter.currency(profit, signed: true, hidden: hidden),
                    shareText: nil
                ))
            case .breakEven, .noQuote:
                break
            }
        }
        return entries
    }

    func outcomeBadgeText(hidden: Bool) -> String {
        if hidden { return "••••" }
        switch profitState {
        case .noQuote:
            return "待获取金价"
        case .profit:
            return "浮盈 " + GoldCalculationFormatter.currency(profit, signed: true)
        case .loss:
            return "浮亏 " + GoldCalculationFormatter.currency(profit, signed: true)
        case .breakEven:
            return "刚好保本"
        }
    }

    func barSummaryText(hidden: Bool) -> String {
        if hidden {
            return "金额已隐藏，关闭隐私遮罩后可查看总投入、预计到手与真实盈亏明细。"
        }
        let costText = GoldCalculationFormatter.currency(totalCost)
        let costDetail: String
        if isManualTotalOnly {
            costDetail = "（手动总价）"
        } else if feesCost > Self.zeroAmountThreshold {
            costDetail = "（含工费与其他 \(GoldCalculationFormatter.currency(feesCost))）"
        } else {
            costDetail = ""
        }

        guard let referencePrice, let proceeds, let profit else {
            return "共投入 \(costText)\(costDetail)，真实保本金价为 \(GoldCalculationFormatter.unitPrice(breakEvenPrice))；获取参考金价后即可对比预计到手与盈亏。"
        }

        let priceText = GoldCalculationFormatter.unitPrice(referencePrice)
        let proceedsText = GoldCalculationFormatter.currency(proceeds)
        let profitText = GoldCalculationFormatter.currency(profit, signed: true)
        if profitState == .breakEven {
            return "共投入 \(costText)\(costDetail)，按当前 \(priceText) 卖出预计到手 \(proceedsText)，当前估算刚好保本。"
        }
        return "共投入 \(costText)\(costDetail)，按当前 \(priceText) 卖出预计到手 \(proceedsText)，两者差额即真实盈亏 \(profitText)。"
    }

    func breakEvenDistanceBadgeText(hidden: Bool) -> String {
        if hidden { return "••••" }
        guard let distance = distanceFromBreakEven else {
            return "获取参考金价后显示"
        }
        if distance <= -Self.zeroAmountThreshold {
            return "还需涨 \(GoldCalculationFormatter.unitPrice(-distance)) 回本"
        }
        if distance >= Self.zeroAmountThreshold {
            return "已超保本线 \(GoldCalculationFormatter.unitPrice(distance))"
        }
        return "已达到真实保本线"
    }

    func breakEvenExplanationText(hidden: Bool) -> String {
        if hidden {
            return "买入工费、纯度折算与回收规则都会摊薄到每克有效含金量上，因此真实保本金价通常高于裸金买入价。"
        }
        if breakEvenDilution < Self.zeroAmountThreshold {
            return "当前无额外工费、纯度折算或回收扣费，真实保本金价与\(baseUnitPriceLabel)一致。"
        }
        var factors: [String] = []
        if !hasManualTotalCost && feesCost > Self.zeroAmountThreshold {
            factors.append("工费与其他成本（\(GoldCalculationFormatter.currency(feesCost))）")
        }
        if hasPurityDiscount {
            factors.append("纯度折算")
        }
        if someCustomRecoveryRules {
            factors.append("回收扣费规则")
        }
        if factors.isEmpty {
            factors.append("有效含金量折算与持仓规则")
        }
        let joined = factors.joined(separator: "、")
        let spread = GoldCalculationFormatter.unitPrice(breakEvenDilution)
        return "\(joined)都会摊到每克有效含金量上，因此真实保本金价需要比\(baseUnitPriceLabel)高出 \(spread)。"
    }
}

// MARK: - 「怎么算的？」可视化 Sheet

struct GoldCalculationSheet: View {
    let records: [HoldingRecord]
    let quote: GoldQuote?
    let basis: GoldMarketBasis
    var hideAmounts = false
    var quoteFailed = false

    @Environment(\.dismiss) private var dismiss
    @State private var selectedScope: GoldCalculationScope = .summary
    @State private var isParametersExpanded = false

    private var items: [GoldCalculationItem] {
        records.map(GoldCalculationItem.init(record:))
    }

    private var effectiveScope: GoldCalculationScope {
        if items.count <= 1, let first = items.first {
            return .item(first.id)
        }
        return selectedScope
    }

    private var activeBreakdown: GoldCalculationBreakdown? {
        GoldCalculationBreakdown.make(
            items: items,
            scope: effectiveScope,
            referencePrice: quote?.cnyPerGram
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if items.count > 1 {
                        scopeSelectorBar
                    }

                    referencePriceHeaderCard

                    if let breakdown = activeBreakdown {
                        comparisonBarCard(breakdown)
                        breakEvenRulerCard(breakdown)
                        parametersDisclosureCard(breakdown)
                    } else {
                        emptyStateCard
                    }

                    disclaimerFooter
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .foregroundStyle(GoldTheme.text)
            }
            .background(GoldTheme.background)
            .navigationTitle("怎么算的？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(GoldTheme.gold)
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .presentationDragIndicator(.visible)
    }

    // MARK: - 顶部持仓切换条（多笔时显示）

    private var scopeSelectorBar: some View {
        let nameCounts = Dictionary(grouping: items, by: \.title).mapValues(\.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("全部汇总") {
                    withAnimation(.snappy(duration: 0.24)) {
                        selectedScope = .summary
                    }
                }
                .buttonStyle(GoldCapsuleStyle(isSelected: effectiveScope == .summary))

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let duplicate = (nameCounts[item.title] ?? 0) > 1
                    let label = duplicate ? "\(item.title) · 第\(index + 1)笔" : item.title
                    Button(label) {
                        withAnimation(.snappy(duration: 0.24)) {
                            selectedScope = .item(item.id)
                        }
                    }
                    .buttonStyle(GoldCapsuleStyle(isSelected: effectiveScope == .item(item.id)))
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 参考金价顶栏

    private var referencePriceHeaderCard: some View {
        let validPrice = GoldReturnCalculator.validPrice(quote?.cnyPerGram)
        let basisBadge = basis == .domestic ? "国内 Au99.99" : "国际伦敦金折算"
        let basisDetail = basis == .domestic
            ? "上海黄金交易所 Au99.99 国内参考价"
            : "国际伦敦金按行情汇率折算人民币/克，非品牌零售价"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("当前参考金价")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text(basisBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
                    }
                    Text(basisDetail)
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if hideAmounts {
                        Text("••••")
                            .font(.system(.title3, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.gold)
                    } else if let validPrice {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(GoldCalculationFormatter.currency(validPrice))
                                .font(.system(.title3, design: .rounded).bold())
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.gold)
                            Text("/g")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                    } else {
                        Text("暂不可用")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                }
            }

            Divider().overlay(GoldTheme.cardStroke)

            HStack(spacing: 6) {
                Circle()
                    .fill(validPrice != nil && !quoteFailed ? GoldTheme.gold : GoldTheme.textFaint)
                    .frame(width: 6, height: 6)
                Text(GoldReturnPresentation.quoteStatus(quote, basis: basis, failed: quoteFailed))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .goldCard(padding: 14)
    }

    // MARK: - 核心视觉 1：总投入 vs 现在卖预计到手 并排堆叠柱状图

    private func comparisonBarCard(_ breakdown: GoldCalculationBreakdown) -> some View {
        let outcomeColor: Color = {
            if hideAmounts { return GoldTheme.textSecondary }
            switch breakdown.profitState {
            case .profit: return GoldTheme.up
            case .loss: return GoldTheme.down
            case .breakEven, .noQuote: return GoldTheme.textSecondary
            }
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总投入 vs 预计到手")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(breakdown.isSummary ? "全部 \(breakdown.recordCount) 笔汇总对比" : breakdown.title)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text(breakdown.outcomeBadgeText(hidden: hideAmounts))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(outcomeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(outcomeColor.opacity(0.14), in: GoldTheme.capsuleShape)
                    .fixedSize()
            }

            GoldComparisonStackedChart(breakdown: breakdown, hidden: hideAmounts)

            compactLegendGrid(breakdown)

            Text(breakdown.barSummaryText(hidden: hideAmounts))
                .font(.caption)
                .foregroundStyle(GoldTheme.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GoldTheme.calendarCell, in: GoldTheme.subCardShape)
        }
        .goldCard()
    }

    private func compactLegendGrid(_ breakdown: GoldCalculationBreakdown) -> some View {
        let entries = breakdown.legendEntries(hidden: hideAmounts)
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    legendSwatch(for: entry.kind)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(entry.amountText)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(legendValueColor(for: entry.kind))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if let share = entry.shareText {
                                Text(share)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textFaint)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func legendSwatch(for kind: GoldCalculationBreakdown.LegendKind) -> some View {
        switch kind {
        case .rawGold:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(GoldTheme.gold)
                .frame(width: 10, height: 10)
        case .fees:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(GoldTheme.chartTertiary)
                .frame(width: 10, height: 10)
        case .manualTotal:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(GoldTheme.gold.opacity(0.82))
                .frame(width: 10, height: 10)
        case .proceeds:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(GoldTheme.goldSoft)
                .frame(width: 10, height: 10)
        case .loss:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(GoldTheme.textSecondary.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(GoldTheme.textSecondary.opacity(0.6), lineWidth: 0.8)
                )
                .frame(width: 10, height: 10)
        case .profitGain:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(hideAmounts ? GoldTheme.textFaint : GoldTheme.up)
                .frame(width: 10, height: 10)
        case .profitLoss:
            if hideAmounts {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(GoldTheme.textFaint)
                    .frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(GoldTheme.down.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(GoldTheme.down, style: StrokeStyle(lineWidth: 1, dash: [2.5, 1.5]))
                    )
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func legendValueColor(for kind: GoldCalculationBreakdown.LegendKind) -> Color {
        if hideAmounts { return GoldTheme.text }
        switch kind {
        case .profitGain: return GoldTheme.up
        case .profitLoss: return GoldTheme.down
        case .loss: return GoldTheme.textSecondary
        default: return GoldTheme.text
        }
    }

    // MARK: - 核心视觉 2：每克保本价构成尺

    private func breakEvenRulerCard(_ breakdown: GoldCalculationBreakdown) -> some View {
        let distanceColor: Color = {
            if hideAmounts { return GoldTheme.textSecondary }
            guard let distance = breakdown.distanceFromBreakEven else { return GoldTheme.textSecondary }
            if distance <= -0.005 { return GoldTheme.down }
            if distance >= 0.005 { return GoldTheme.up }
            return GoldTheme.gold
        }()

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("每克保本价构成尺")
                    .font(.headline)
                Text("同一克价比例尺对比，看清保本线为什么高于买价")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }

            GoldBreakEvenRulerView(breakdown: breakdown, hidden: hideAmounts)

            // 三个核心克价节点
            HStack(spacing: 8) {
                priceNodeCell(
                    dotColor: GoldTheme.goldSoft,
                    label: "当前参考价",
                    value: GoldCalculationFormatter.unitPrice(breakdown.referencePrice, hidden: hideAmounts)
                )
                priceNodeCell(
                    dotColor: GoldTheme.gold,
                    label: breakdown.baseUnitPriceLabel,
                    value: GoldCalculationFormatter.unitPrice(breakdown.baseUnitPrice, hidden: hideAmounts)
                )
                priceNodeCell(
                    dotColor: GoldTheme.chartTertiary,
                    label: "真实保本价",
                    value: GoldCalculationFormatter.unitPrice(breakdown.breakEvenPrice, hidden: hideAmounts),
                    emphasized: true
                )
            }

            // 两段关键差额卡片
            let distanceTitle = hideAmounts
                ? "与保本线距离"
                : (breakdown.profitState == .profit ? "盈亏安全垫" : "距离回本还差")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    spreadCalloutCell(
                        title: breakdown.dilutionLabel,
                        value: GoldCalculationFormatter.unitPrice(breakdown.breakEvenDilution, signed: true, hidden: hideAmounts),
                        accent: hideAmounts ? GoldTheme.textSecondary : GoldTheme.chartTertiary
                    )
                    spreadCalloutCell(
                        title: distanceTitle,
                        value: breakdown.breakEvenDistanceBadgeText(hidden: hideAmounts),
                        accent: distanceColor
                    )
                }
                VStack(spacing: 10) {
                    spreadCalloutCell(
                        title: breakdown.dilutionLabel,
                        value: GoldCalculationFormatter.unitPrice(breakdown.breakEvenDilution, signed: true, hidden: hideAmounts),
                        accent: hideAmounts ? GoldTheme.textSecondary : GoldTheme.chartTertiary
                    )
                    spreadCalloutCell(
                        title: distanceTitle,
                        value: breakdown.breakEvenDistanceBadgeText(hidden: hideAmounts),
                        accent: distanceColor
                    )
                }
            }

            Text(breakdown.breakEvenExplanationText(hidden: hideAmounts))
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .goldCard()
    }

    private func priceNodeCell(
        dotColor: Color,
        label: String,
        value: String,
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(.footnote, design: .rounded).weight(emphasized ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(emphasized ? GoldTheme.gold : GoldTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(GoldTheme.calendarCell, in: GoldTheme.subCardShape)
    }

    private func spreadCalloutCell(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(0.11), in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - 底部折叠区：完整参数与计算公式

    private func parametersDisclosureCard(_ breakdown: GoldCalculationBreakdown) -> some View {
        DisclosureGroup(isExpanded: $isParametersExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                Divider().overlay(GoldTheme.cardStroke)

                // 1. 买入成本
                parameterSection(title: "买入成本") {
                    if let single = breakdown.singleInput {
                        let purityText = hideAmounts
                            ? "••••"
                            : "\(GoldCalculationFormatter.grams(single.grams)) · \(GoldCalculationFormatter.percent(single.purity * 100))"
                        parameterRow("克重 / 纯度", value: purityText)
                        parameterRow(
                            "有效克重",
                            value: GoldCalculationFormatter.grams(single.effectiveGrams, maxFractionDigits: 4, hidden: hideAmounts)
                        )
                        if single.totalCostOverride == nil {
                            parameterRow("裸金单价", value: GoldCalculationFormatter.unitPrice(single.unitPrice, hidden: hideAmounts))
                            parameterRow("裸金成本", value: GoldCalculationFormatter.currency(breakdown.rawGoldCost, hidden: hideAmounts))
                            if single.laborFee > 0 || single.otherCost > 0 {
                                if single.laborFee > 0 {
                                    parameterRow("购入工费", value: GoldCalculationFormatter.currency(single.laborFee, hidden: hideAmounts))
                                }
                                if single.otherCost > 0 {
                                    parameterRow("其他成本", value: GoldCalculationFormatter.currency(single.otherCost, hidden: hideAmounts))
                                }
                            } else {
                                parameterRow("工费 / 其他成本", value: GoldCalculationFormatter.currency(0, hidden: hideAmounts))
                            }
                            parameterRow("总投入", value: GoldCalculationFormatter.currency(breakdown.totalCost, hidden: hideAmounts), emphasized: true)
                        } else {
                            parameterRow("总投入（手动）", value: GoldCalculationFormatter.currency(breakdown.totalCost, hidden: hideAmounts), emphasized: true)
                            Text("手动总价为最终现金支出，不再额外叠加工费与其他成本。")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                    } else {
                        parameterRow("持仓笔数", value: "\(breakdown.recordCount) 笔")
                        parameterRow(
                            "总克重 / 有效克重",
                            value: hideAmounts
                                ? "••••"
                                : "\(GoldCalculationFormatter.grams(breakdown.totalGrams)) / \(GoldCalculationFormatter.grams(breakdown.effectiveGrams, maxFractionDigits: 4))"
                        )
                        if breakdown.rawGoldCost > 0.005 {
                            parameterRow("裸金成本合计", value: GoldCalculationFormatter.currency(breakdown.rawGoldCost, hidden: hideAmounts))
                        }
                        if breakdown.feesCost > 0.005 {
                            parameterRow("工费与其他合计", value: GoldCalculationFormatter.currency(breakdown.feesCost, hidden: hideAmounts))
                        }
                        if breakdown.manualTotalCost > 0.005 {
                            parameterRow("手动总投入合计", value: GoldCalculationFormatter.currency(breakdown.manualTotalCost, hidden: hideAmounts))
                        }
                        parameterRow("总投入合计", value: GoldCalculationFormatter.currency(breakdown.totalCost, hidden: hideAmounts), emphasized: true)
                    }
                }

                Divider().overlay(GoldTheme.cardStroke)

                // 2. 回收规则（默认全 0 时合并为单行去噪）
                parameterSection(title: "回收规则") {
                    if let single = breakdown.singleInput {
                        if single.rule.isDefault {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.gold)
                                Text("尚未计入回收费用")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.gold)
                            }
                        } else {
                            parameterRow("每克回收扣减", value: GoldCalculationFormatter.unitPrice(single.rule.perGramDeduction, hidden: hideAmounts))
                            parameterRow("比例折价", value: GoldCalculationFormatter.percent(single.rule.discountRate * 100, hidden: hideAmounts))
                            parameterRow("固定卖出费用", value: GoldCalculationFormatter.currency(single.rule.fixedFee, hidden: hideAmounts))
                        }
                    } else {
                        if breakdown.allDefaultRecoveryRules {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.gold)
                                Text("尚未计入回收费用")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.gold)
                            }
                        } else {
                            Text("组合内各笔按各自回收规则分别计算；未配置回收费用的持仓不计扣费。")
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                            if let recoveryLoss = breakdown.recoveryLoss, recoveryLoss > 0.01 {
                                parameterRow("回收扣减估算合计", value: GoldCalculationFormatter.currency(-recoveryLoss, hidden: hideAmounts))
                            }
                        }
                    }
                }

                Divider().overlay(GoldTheme.cardStroke)

                // 3. 计算结果
                parameterSection(title: "计算结果") {
                    if breakdown.referencePrice != nil {
                        parameterRow(
                            breakdown.isSummary ? "加权预计回收单价" : "预计回收单价",
                            value: GoldCalculationFormatter.unitPrice(breakdown.recoveryUnitPrice, hidden: hideAmounts)
                        )
                        parameterRow("现在卖预计到手", value: GoldCalculationFormatter.currency(breakdown.proceeds, hidden: hideAmounts))
                        if breakdown.hasVisibleLoss, let totalLoss = breakdown.totalLoss {
                            parameterRow("纯度与回收损耗", value: GoldCalculationFormatter.currency(-totalLoss, hidden: hideAmounts))
                        }
                        parameterRow(
                            "真实盈亏",
                            value: GoldCalculationFormatter.currency(breakdown.profit, signed: true, hidden: hideAmounts),
                            valueColor: profitTextColor(breakdown)
                        )
                        parameterRow(
                            "真实收益率",
                            value: GoldCalculationFormatter.percent(breakdown.profitPercent, signed: true, hidden: hideAmounts),
                            valueColor: profitTextColor(breakdown)
                        )
                    } else {
                        parameterRow("预计到手 / 真实盈亏", value: "待获取参考金价")
                    }
                    parameterRow(
                        "真实保本金价",
                        value: GoldCalculationFormatter.unitPrice(breakdown.breakEvenPrice, hidden: hideAmounts),
                        valueColor: GoldTheme.gold
                    )
                }

                Divider().overlay(GoldTheme.cardStroke)

                // 4. 计算公式
                parameterSection(title: "计算公式") {
                    Text(
                        "有效克重 = 克重 × 纯度\n" +
                        "总投入 = 裸金单价 × 克重 + 工费 + 其他成本（手动总价优先）\n" +
                        "预计回收单价 = max(参考金价 − 每克扣减, 0) × (1 − 比例折价)\n" +
                        "预计到手 = max(预计回收单价 × 有效克重 − 固定费用, 0)\n" +
                        "真实盈亏 = 预计到手 − 总投入\n" +
                        "真实收益率 = 真实盈亏 ÷ 总投入\n" +
                        "真实保本价 = (总投入 + 固定费用) ÷ [有效克重 × (1 − 折价)] + 每克扣减"
                    )
                    .font(.caption)
                    .lineSpacing(5)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if breakdown.isSummary {
                        Text("组合金额逐笔求和；组合保本价按各笔独立规则反推，并非单笔保本价的简单平均。固定费用按每笔独立卖出估算。")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "function")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.gold)
                    .frame(width: 28, height: 28)
                    .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.badgeShape)
                VStack(alignment: .leading, spacing: 2) {
                    Text("查看完整参数与计算公式")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                    Text("买入成本 · 回收规则 · 计算结果 · 公式")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer()
            }
        }
        .tint(GoldTheme.gold)
        .goldCard()
    }

    private func parameterSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(GoldTheme.gold)
            content()
        }
    }

    private func parameterRow(
        _ title: String,
        value: String,
        emphasized: Bool = false,
        valueColor: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(emphasized ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? GoldTheme.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func profitTextColor(_ breakdown: GoldCalculationBreakdown) -> Color {
        if hideAmounts { return GoldTheme.text }
        switch breakdown.profitState {
        case .profit: return GoldTheme.up
        case .loss: return GoldTheme.down
        case .breakEven, .noQuote: return GoldTheme.textSecondary
        }
    }

    // MARK: - 空态与底部免责声明

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无可拆解的持仓记录")
                .font(.subheadline.weight(.semibold))
            Text("录入黄金持仓后，可在此查看总投入与预计到手的直观对比及每克保本价构成。")
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .goldCard()
    }

    private var disclaimerFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(GoldTheme.gold)
                .padding(.top, 1)
            Text("当前结果仅为估算参考，真实成交价可能因渠道、纯度检测与手续费变化，不构成任何投资或买卖建议。")
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - 子视图：并排双堆叠柱状图

private struct GoldComparisonStackedChart: View {
    let breakdown: GoldCalculationBreakdown
    let hidden: Bool

    private let chartHeight: CGFloat = 224
    private let topHeadroom: CGFloat = 38

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let plotHeight = max(120, geo.size.height - topHeadroom)
                let barWidth = min(92, max(62, geo.size.width * 0.29))
                let columnGap = min(48, max(20, geo.size.width - barWidth * 2 - 40))

                let leftRatio: CGFloat = hidden
                    ? 0.78
                    : CGFloat(max(0, min(1, breakdown.totalCost / breakdown.barMaxValue)))
                let leftHeight = max(breakdown.totalCost > 0 ? 6 : 0, plotHeight * leftRatio)

                ZStack(alignment: .bottom) {
                    // 背景参考网格线
                    VStack(spacing: 0) {
                        Spacer(minLength: topHeadroom)
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 0) {
                                Rectangle().fill(GoldTheme.gridline).frame(height: 1)
                                Spacer()
                                Rectangle().fill(GoldTheme.gridline).frame(height: 1)
                                Spacer()
                                Rectangle().fill(GoldTheme.cardStroke).frame(height: 1)
                            }
                            .frame(height: plotHeight)

                            // 左柱顶线水平参考虚线（存在金价且非隐私遮罩时显示）
                            if breakdown.referencePrice != nil && !hidden && leftHeight > 0 {
                                DashedHorizontalLine()
                                    .stroke(GoldTheme.textSecondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .frame(height: 1)
                                    .offset(y: -leftHeight)
                            }
                        }
                        .frame(height: plotHeight)
                    }

                    // 并排双柱
                    HStack(alignment: .bottom, spacing: columnGap) {
                        leftCostColumn(barWidth: barWidth, plotHeight: plotHeight, barHeight: leftHeight)
                        rightProceedsColumn(barWidth: barWidth, plotHeight: plotHeight, leftHeight: leftHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight)

            // X 轴柱名
            HStack(spacing: 24) {
                Text("总投入")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                    .frame(maxWidth: .infinity)
                Text("现在卖预计到手")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func leftCostColumn(barWidth: CGFloat, plotHeight: CGFloat, barHeight: CGFloat) -> some View {
        let topValue = GoldCalculationFormatter.currency(breakdown.totalCost, hidden: hidden)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 10,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 4,
            topTrailingRadius: 10,
            style: .continuous
        )

        return VStack(spacing: 6) {
            Text(topValue)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if hidden {
                shape
                    .fill(GoldTheme.gold.opacity(0.65))
                    .frame(width: barWidth, height: barHeight)
            } else {
                // 自上而下渲染堆叠：工费/手动在上方，裸金成本在底部稳固托底
                let ordered = breakdown.costSegments.reversed()
                VStack(spacing: 1) {
                    ForEach(Array(ordered)) { segment in
                        let segHeight = max(2, barHeight * CGFloat(segment.share))
                        Rectangle()
                            .fill(segmentColor(segment.kind))
                            .frame(height: segHeight)
                    }
                }
                .frame(width: barWidth, height: barHeight, alignment: .bottom)
                .clipShape(shape)
            }
        }
        .frame(width: max(barWidth + 28, 112), alignment: .bottom)
    }

    @ViewBuilder
    private func rightProceedsColumn(barWidth: CGFloat, plotHeight: CGFloat, leftHeight: CGFloat) -> some View {
        if hidden {
            let maskedHeight = plotHeight * 0.60
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: 4,
                topTrailingRadius: 10,
                style: .continuous
            )
            VStack(spacing: 6) {
                Text("••••")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
                shape
                    .fill(GoldTheme.goldSoft.opacity(0.65))
                    .frame(width: barWidth, height: maskedHeight)
            }
            .frame(width: max(barWidth + 28, 112), alignment: .bottom)
        } else if let proceeds = breakdown.proceeds {
            let proceedsRatio = CGFloat(max(0, min(1, proceeds / breakdown.barMaxValue)))
            let proceedsHeight = max(proceeds > 0 ? 4 : 0, plotHeight * proceedsRatio)
            let lossAmount = breakdown.hasVisibleLoss ? (breakdown.totalLoss ?? 0) : 0
            let lossRatio = CGFloat(max(0, min(1, lossAmount / breakdown.barMaxValue)))
            let rawLossHeight = lossAmount > 0 ? max(3, plotHeight * lossRatio) : 0
            let lossTop = min(plotHeight, proceedsHeight + rawLossHeight)
            let clampedLossHeight = max(0, lossTop - proceedsHeight)
            let visualTop = max(
                proceedsHeight + clampedLossHeight,
                breakdown.profitState == .loss ? leftHeight : 0
            )

            let barShape = UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: 4,
                topTrailingRadius: 10,
                style: .continuous
            )

            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    if breakdown.profitState == .loss && (leftHeight - proceedsHeight) < 38 {
                        Text("浮亏 \(GoldCalculationFormatter.currency(breakdown.profit, signed: true))")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.down)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else if breakdown.profitState == .profit && (proceedsHeight - leftHeight) < 34 {
                        Text("浮盈 \(GoldCalculationFormatter.currency(breakdown.profit, signed: true))")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.up)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(GoldCalculationFormatter.currency(proceeds))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.goldSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                ZStack(alignment: .bottom) {
                    switch breakdown.profitState {
                    case .loss:
                        // 1. 预计到手实心柱
                        if proceedsHeight > 0 {
                            UnevenRoundedRectangle(
                                topLeadingRadius: leftHeight - proceedsHeight > 4 ? 3 : 10,
                                bottomLeadingRadius: 4,
                                bottomTrailingRadius: 4,
                                topTrailingRadius: leftHeight - proceedsHeight > 4 ? 3 : 10,
                                style: .continuous
                            )
                            .fill(GoldTheme.goldSoft)
                            .frame(width: barWidth, height: proceedsHeight)
                        }

                        // 2. 纯度与回收损耗（紧贴预计到手上方）
                        if clampedLossHeight > 0 {
                            Rectangle()
                                .fill(GoldTheme.textSecondary.opacity(0.32))
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(GoldTheme.textSecondary.opacity(0.55), lineWidth: 0.7)
                                )
                                .frame(width: barWidth, height: clampedLossHeight)
                                .offset(y: -proceedsHeight)
                        }

                        // 3. 绿色半透明虚线框：严格补齐至左柱顶线，直观展现浮亏差额
                        let deficitHeight = max(0, leftHeight - proceedsHeight)
                        if deficitHeight > 1 {
                            let deficitShape = UnevenRoundedRectangle(
                                topLeadingRadius: 10,
                                bottomLeadingRadius: proceedsHeight > 0 ? 2 : 4,
                                bottomTrailingRadius: proceedsHeight > 0 ? 2 : 4,
                                topTrailingRadius: 10,
                                style: .continuous
                            )
                            deficitShape
                                .fill(GoldTheme.down.opacity(0.13))
                                .overlay(
                                    deficitShape.strokeBorder(
                                        GoldTheme.down,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                                    )
                                )
                                .overlay {
                                    if deficitHeight >= 38 {
                                        VStack(spacing: 2) {
                                            Text("浮亏")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(GoldTheme.down)
                                            Text(GoldCalculationFormatter.currency(breakdown.profit, signed: true))
                                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                                .monospacedDigit()
                                                .foregroundStyle(GoldTheme.down)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.62)
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .frame(width: barWidth, height: deficitHeight)
                                .offset(y: -proceedsHeight)
                        }

                    case .profit:
                        let baseHeight = min(leftHeight, proceedsHeight)
                        let profitHeight = max(0, proceedsHeight - baseHeight)

                        // 整体按统一比例堆叠：底部回本到手 + 红色浮盈块 + 顶部灰色损耗段
                        VStack(spacing: 0) {
                            if clampedLossHeight > 0 {
                                Rectangle()
                                    .fill(GoldTheme.textSecondary.opacity(0.32))
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(GoldTheme.textSecondary.opacity(0.55), lineWidth: 0.7)
                                    )
                                    .frame(height: clampedLossHeight)
                            }
                            if profitHeight > 0 {
                                ZStack {
                                    Rectangle().fill(GoldTheme.up)
                                    if profitHeight >= 34 {
                                        VStack(spacing: 1) {
                                            Text("浮盈")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(GoldTheme.text)
                                            Text(GoldCalculationFormatter.currency(breakdown.profit, signed: true))
                                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                                .monospacedDigit()
                                                .foregroundStyle(GoldTheme.text)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.62)
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .frame(height: profitHeight)
                            }
                            if baseHeight > 0 {
                                Rectangle()
                                    .fill(GoldTheme.goldSoft)
                                    .frame(height: baseHeight)
                            }
                        }
                        .frame(width: barWidth, height: proceedsHeight + clampedLossHeight, alignment: .bottom)
                        .clipShape(barShape)

                    case .breakEven, .noQuote:
                        VStack(spacing: 0) {
                            if clampedLossHeight > 0 {
                                Rectangle()
                                    .fill(GoldTheme.textSecondary.opacity(0.32))
                                    .frame(height: clampedLossHeight)
                            }
                            Rectangle()
                                .fill(GoldTheme.goldSoft)
                                .frame(height: proceedsHeight)
                        }
                        .frame(width: barWidth, height: proceedsHeight + clampedLossHeight, alignment: .bottom)
                        .clipShape(barShape)
                    }
                }
                .frame(width: barWidth, height: max(visualTop, 4), alignment: .bottom)
            }
            .frame(width: max(barWidth + 28, 112), alignment: .bottom)
        } else {
            // 无参考金价降级占位柱
            let placeholderHeight = max(84, leftHeight)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 4,
                bottomTrailingRadius: 4,
                topTrailingRadius: 10,
                style: .continuous
            )
            VStack(spacing: 6) {
                Text("—")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(GoldTheme.textSecondary)
                shape
                    .fill(GoldTheme.calendarCell.opacity(0.7))
                    .overlay(
                        shape.strokeBorder(
                            GoldTheme.textFaint.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])
                        )
                    )
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.subheadline)
                                .foregroundStyle(GoldTheme.textSecondary)
                            Text("获取参考金价后\n显示预计到手对比")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                    }
                    .frame(width: barWidth, height: placeholderHeight)
            }
            .frame(width: max(barWidth + 28, 112), alignment: .bottom)
        }
    }

    private func segmentColor(_ kind: GoldCalculationBreakdown.CostSegmentKind) -> Color {
        switch kind {
        case .rawGold: GoldTheme.gold
        case .fees: GoldTheme.chartTertiary
        case .manualTotal: GoldTheme.gold.opacity(0.82)
        }
    }
}

// MARK: - 子视图：每克保本价构成尺

private struct GoldBreakEvenRulerView: View {
    let breakdown: GoldCalculationBreakdown
    let hidden: Bool

    var body: some View {
        let maxPrice = breakdown.rulerMaxPrice
        let baseRatio: CGFloat = hidden ? 0.62 : CGFloat(max(0, min(1, breakdown.baseUnitPrice / maxPrice)))
        let breakEvenRatio: CGFloat = hidden ? 0.78 : CGFloat(max(baseRatio, min(1, breakdown.breakEvenPrice / maxPrice)))
        let refRatio: CGFloat? = hidden
            ? 0.48
            : breakdown.referencePrice.map { CGFloat(max(0, min(1, $0 / maxPrice))) }

        VStack(alignment: .leading, spacing: 10) {
            // Track 1: 真实保本金价构成 = 裸金均价 + 摊薄
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("保本价构成")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer()
                    Text(GoldCalculationFormatter.unitPrice(breakdown.breakEvenPrice, hidden: hidden))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.gold)
                }

                GeometryReader { geo in
                    let width = max(1, geo.size.width)
                    let baseW = width * baseRatio
                    let breakEvenW = width * breakEvenRatio
                    let dilutionW = max(0, breakEvenW - baseW)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(GoldTheme.calendarCell)
                            .frame(height: 14)

                        HStack(spacing: 0) {
                            if baseW > 0 {
                                Rectangle()
                                    .fill(GoldTheme.gold)
                                    .frame(width: baseW, height: 14)
                            }
                            if dilutionW > 0.5 && !hidden {
                                Rectangle()
                                    .fill(GoldTheme.chartTertiary)
                                    .frame(width: dilutionW, height: 14)
                            } else if hidden && dilutionW > 0 {
                                Rectangle()
                                    .fill(GoldTheme.chartTertiary.opacity(0.65))
                                    .frame(width: dilutionW, height: 14)
                            }
                        }
                        .clipShape(Capsule())

                        // 保本线刻度标记
                        Rectangle()
                            .fill(GoldTheme.text)
                            .frame(width: 2, height: 18)
                            .offset(x: max(0, min(width - 2, breakEvenW - 1)))
                    }
                }
                .frame(height: 18)
            }

            // Track 2: 当前参考金价与保本线对比
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("当前金价对比")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer()
                    Text(
                        breakdown.referencePrice != nil
                            ? GoldCalculationFormatter.unitPrice(breakdown.referencePrice, hidden: hidden)
                            : (hidden ? "••••" : "暂不可用")
                    )
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
                }

                GeometryReader { geo in
                    let width = max(1, geo.size.width)
                    let breakEvenX = width * breakEvenRatio

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(GoldTheme.calendarCell)
                            .frame(height: 14)

                        if hidden {
                            Capsule()
                                .fill(GoldTheme.goldSoft.opacity(0.65))
                                .frame(width: width * (refRatio ?? 0.48), height: 14)
                        } else if let refRatio {
                            let refW = width * refRatio
                            if refW < breakEvenX {
                                // 亏损：当前价 + 绿色虚线缺口至保本线
                                let gapW = max(0, breakEvenX - refW)
                                if refW > 0 {
                                    Capsule()
                                        .fill(GoldTheme.goldSoft)
                                        .frame(width: max(6, refW), height: 14)
                                }
                                if gapW > 2 {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(GoldTheme.down.opacity(0.16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(GoldTheme.down, style: StrokeStyle(lineWidth: 1.2, dash: [4, 2.5]))
                                        )
                                        .frame(width: gapW, height: 14)
                                        .offset(x: refW)
                                }
                            } else {
                                // 盈利或刚好保本：保本线内淡金 + 超出部分红色实心
                                let excessW = max(0, refW - breakEvenX)
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(GoldTheme.goldSoft)
                                        .frame(width: breakEvenX, height: 14)
                                    if excessW > 0.5 {
                                        Rectangle()
                                            .fill(GoldTheme.up)
                                            .frame(width: excessW, height: 14)
                                    }
                                }
                                .clipShape(Capsule())
                            }
                        } else {
                            Capsule()
                                .strokeBorder(GoldTheme.textFaint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(height: 14)
                        }

                        // 与上轨对齐的保本参考刻度线
                        Rectangle()
                            .fill(GoldTheme.text.opacity(0.75))
                            .frame(width: 2, height: 18)
                            .offset(x: max(0, min(width - 2, breakEvenX - 1)))
                    }
                }
                .frame(height: 18)
            }
        }
        .padding(12)
        .background(GoldTheme.background.opacity(0.55), in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
        )
    }
}

private struct DashedHorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}
