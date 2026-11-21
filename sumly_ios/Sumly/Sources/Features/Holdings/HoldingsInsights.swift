import Foundation

/// 持仓结构分析切片（按品类或品牌汇总）。
struct HoldingAllocationSlice: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let grams: Double
    let totalCost: Double
    let count: Int
    /// 占总克重比例（0...1）。
    let gramShare: Double
    /// 占总投入比例（0...1）。
    let costShare: Double
}

/// 攒金目标进度模型。
struct GoldSavingGoalProgress: Equatable, Sendable {
    let targetGrams: Double
    let currentGrams: Double
    let remainingGrams: Double
    /// 真实完成率（可大于 1.0）。
    let rawProgress: Double
    /// 用于进度条展示的 0...1 进度值。
    let clampedProgress: Double
    let isAchieved: Bool
    /// 按当前参考金价估算达成目标还需投入金额。
    let estimatedRemainingCost: Double?

    static func make(targetGrams: Double, currentGrams: Double, referencePrice: Double?) -> GoldSavingGoalProgress? {
        guard targetGrams.isFinite, targetGrams > 0, currentGrams.isFinite, currentGrams >= 0 else { return nil }
        let remaining = max(0, targetGrams - currentGrams)
        let raw = currentGrams / targetGrams
        let budget: Double? = {
            guard remaining > 0, let price = referencePrice, price.isFinite, price > 0 else { return nil }
            return remaining * price
        }()
        return GoldSavingGoalProgress(
            targetGrams: targetGrams,
            currentGrams: currentGrams,
            remainingGrams: remaining,
            rawProgress: raw,
            clampedProgress: min(1, max(0, raw)),
            isAchieved: currentGrams >= targetGrams,
            estimatedRemainingCost: budget
        )
    }
}

/// 行情走势图上的持仓叠加信息：组合保本线、加权成本均线与区间内买入打点。
struct MarketHoldingOverlay: Equatable, Sendable {
    struct PurchaseItem: Identifiable, Equatable, Sendable {
        let id: UUID
        let assetType: String
        let brand: String
        let grams: Double
        let unitPrice: Double
        let effectiveUnitCost: Double
        let totalCost: Double
        let laborFee: Double
        let timestamp: Date
        let note: String

        var resolvedAssetType: GoldAssetType {
            GoldAssetType(rawValue: assetType.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .other
        }

        var displayName: String {
            let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBrand.isEmpty { return trimmedBrand }
            let trimmedType = assetType.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedType.isEmpty || trimmedType == "其他" ? "黄金记录" : trimmedType
        }
    }

    struct PurchaseMarker: Identifiable, Equatable, Sendable {
        let date: Date
        let totalGrams: Double
        let averageUnitPrice: Double
        let count: Int
        let items: [PurchaseItem]
        let minUnitCost: Double
        let maxUnitCost: Double

        var id: Date { date }

        init(
            date: Date,
            totalGrams: Double,
            averageUnitPrice: Double,
            count: Int,
            items: [PurchaseItem] = [],
            minUnitCost: Double? = nil,
            maxUnitCost: Double? = nil
        ) {
            self.date = date
            self.totalGrams = totalGrams
            self.averageUnitPrice = averageUnitPrice
            self.count = count
            self.items = items
            let validCosts = items.map(\.effectiveUnitCost).filter { $0.isFinite && $0 > 0 }
            self.minUnitCost = minUnitCost ?? validCosts.min() ?? averageUnitPrice
            self.maxUnitCost = maxUnitCost ?? validCosts.max() ?? averageUnitPrice
        }
    }

    let breakEvenPrice: Double?
    let averageCostPerGram: Double?
    let totalGrams: Double
    let markers: [PurchaseMarker]

    var hasContent: Bool {
        breakEvenPrice != nil || averageCostPerGram != nil || !markers.isEmpty
    }
}

/// 一键快捷记账预设模板：覆盖主流购金场景，不覆写用户已手填克重/单价。
enum HoldingQuickPreset: String, CaseIterable, Identifiable, Sendable {
    case bankAccumulation = "积存金"
    case investmentBar = "投资金条"
    case brandJewelry = "品牌金饰"
    case shuibeiJewelry = "水贝金饰"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .bankAccumulation: "0工费 · 99.99%"
        case .investmentBar: "低工费 · 99.99%"
        case .brandJewelry: "按克工费 · 99.9%"
        case .shuibeiJewelry: "低工费 · 99.99%"
        }
    }

    var symbol: String {
        switch self {
        case .bankAccumulation: "building.columns"
        case .investmentBar: "rectangle.stack.fill"
        case .brandJewelry: "sparkles"
        case .shuibeiJewelry: "diamond"
        }
    }

    /// 按预设填充合理默认值；保留用户已输入的克重、单价、总价与备注。
    func apply(to draft: inout HoldingDraft) {
        switch self {
        case .bankAccumulation:
            draft.assetType = .accumulation
            draft.purityText = "99.99"
            draft.laborPerGram = true
            draft.laborText = "0"
            draft.deductionText = ""
            draft.discountText = "0.5"
            draft.fixedFeeText = ""
        case .investmentBar:
            draft.assetType = .bar
            draft.purityText = "99.99"
            draft.laborPerGram = true
            draft.laborText = "10"
            draft.deductionText = "3"
            draft.discountText = ""
            draft.fixedFeeText = ""
        case .brandJewelry:
            draft.assetType = .jewelry
            draft.purityText = "99.9"
            draft.laborPerGram = true
            draft.laborText = "60"
            draft.deductionText = "15"
            draft.discountText = ""
            draft.fixedFeeText = ""
        case .shuibeiJewelry:
            draft.assetType = .jewelry
            draft.purityText = "99.99"
            draft.laborPerGram = true
            draft.laborText = "15"
            draft.deductionText = "5"
            draft.discountText = ""
            draft.fixedFeeText = ""
        }
    }
}

/// 持仓洞察纯逻辑汇总。
enum HoldingsInsights {
    struct Entry: Sendable {
        let id: UUID?
        let assetType: String
        let brand: String
        let channel: String
        let grams: Double
        let totalCost: Double
        let unitPrice: Double
        let laborFee: Double
        let timestamp: Date
        let note: String
        let input: GoldReturnInput

        init(
            id: UUID? = nil,
            assetType: String,
            brand: String,
            channel: String,
            grams: Double,
            totalCost: Double,
            unitPrice: Double,
            laborFee: Double = 0,
            timestamp: Date,
            note: String = "",
            input: GoldReturnInput
        ) {
            self.id = id
            self.assetType = assetType
            self.brand = brand
            self.channel = channel
            self.grams = grams
            self.totalCost = totalCost
            self.unitPrice = unitPrice
            self.laborFee = laborFee
            self.timestamp = timestamp
            self.note = note
            self.input = input
        }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case assetType = "按品类"
        case brand = "按品牌"
        var id: String { rawValue }
    }

    static func allocations(from entries: [Entry], grouping: Grouping) -> [HoldingAllocationSlice] {
        guard !entries.isEmpty else { return [] }
        let totalGrams = entries.reduce(0) { $0 + max(0, $1.grams) }
        let totalCost = entries.reduce(0) { $0 + max(0, $1.totalCost) }
        guard totalGrams > 0 else { return [] }

        var buckets: [String: (grams: Double, cost: Double, count: Int)] = [:]
        for entry in entries where entry.grams > 0 {
            let key: String
            switch grouping {
            case .assetType:
                let cleaned = entry.assetType.trimmingCharacters(in: .whitespacesAndNewlines)
                key = cleaned.isEmpty ? "其他" : cleaned
            case .brand:
                let cleaned = entry.brand.trimmingCharacters(in: .whitespacesAndNewlines)
                key = cleaned.isEmpty ? "未填品牌" : cleaned
            }
            var current = buckets[key] ?? (0, 0, 0)
            current.grams += entry.grams
            current.cost += max(0, entry.totalCost)
            current.count += 1
            buckets[key] = current
        }

        return buckets.map { label, data in
            HoldingAllocationSlice(
                id: label,
                label: label,
                grams: data.grams,
                totalCost: data.cost,
                count: data.count,
                gramShare: data.grams / totalGrams,
                costShare: totalCost > 0 ? data.cost / totalCost : 0
            )
        }.sorted {
            if $0.grams != $1.grams { return $0.grams > $1.grams }
            return $0.label < $1.label
        }
    }

    /// 提取最近常用的品牌或渠道标签，便于一键填入。
    static func recentTags(from entries: [Entry], keyPath: KeyPath<Entry, String>, limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let value = entry[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }

    /// 为行情走势图生成叠加数据（组合保本线、成本均线、区间内历史买入打点）。
    static func marketOverlay(entries: [Entry], window: ClosedRange<Date>, referencePrice: Double?, calendar: Calendar = .current) -> MarketHoldingOverlay? {
        let valid = entries.filter { $0.grams > 0 && $0.input.isValid }
        guard !valid.isEmpty else { return nil }

        let portfolio = GoldReturnCalculator.aggregate(valid.map(\.input), referencePrice: referencePrice)
        let totalGrams = valid.reduce(0) { $0 + $1.grams }
        let totalCost = valid.reduce(0) { $0 + $1.totalCost }
        let averageCost = totalGrams > 0 ? totalCost / totalGrams : nil

        var dayBuckets: [Date: (grams: Double, weightedCost: Double, items: [MarketHoldingOverlay.PurchaseItem])] = [:]
        for entry in valid {
            let day = ChartViewport.noon(entry.timestamp, calendar: calendar)
            guard window.contains(day) else { continue }
            var bucket = dayBuckets[day] ?? (0, 0, [])
            let effectiveUnitCost = entry.grams > 0 ? entry.totalCost / entry.grams : entry.unitPrice
            let resolvedLaborFee = entry.laborFee > 0 ? entry.laborFee : entry.input.laborFee
            let item = MarketHoldingOverlay.PurchaseItem(
                id: entry.id ?? UUID(),
                assetType: entry.assetType,
                brand: entry.brand,
                grams: entry.grams,
                unitPrice: entry.unitPrice,
                effectiveUnitCost: effectiveUnitCost,
                totalCost: entry.totalCost,
                laborFee: resolvedLaborFee,
                timestamp: entry.timestamp,
                note: entry.note
            )
            bucket.grams += entry.grams
            bucket.weightedCost += entry.totalCost
            bucket.items.append(item)
            dayBuckets[day] = bucket
        }

        let markers = dayBuckets.map { day, bucket in
            let sortedItems = bucket.items.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
                if lhs.effectiveUnitCost != rhs.effectiveUnitCost { return lhs.effectiveUnitCost > rhs.effectiveUnitCost }
                return lhs.displayName < rhs.displayName
            }
            let averageUnitPrice = bucket.grams > 0 ? bucket.weightedCost / bucket.grams : 0
            return MarketHoldingOverlay.PurchaseMarker(
                date: day,
                totalGrams: bucket.grams,
                averageUnitPrice: averageUnitPrice,
                count: sortedItems.count,
                items: sortedItems
            )
        }.sorted { $0.date < $1.date }

        let overlay = MarketHoldingOverlay(
            breakEvenPrice: portfolio?.breakEvenPrice,
            averageCostPerGram: averageCost,
            totalGrams: totalGrams,
            markers: markers
        )
        return overlay.hasContent ? overlay : nil
    }
}

extension HoldingRecord {
    var insightEntry: HoldingsInsights.Entry {
        HoldingsInsights.Entry(
            id: id,
            assetType: assetType,
            brand: brand,
            channel: purchaseChannel,
            grams: grams,
            totalCost: totalPurchaseCost,
            unitPrice: unitPriceCNY,
            laborFee: laborFee,
            timestamp: timestamp,
            note: note,
            input: returnInput
        )
    }
}
