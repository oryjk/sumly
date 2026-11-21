import Foundation

// MARK: - 视图模式、图层与语义状态

enum GoldCalendarViewTab: String, CaseIterable, Identifiable, Sendable {
    case month = "月历"
    case year = "年览"
    case stats = "统计"

    var id: String { rawValue }
}

enum GoldCalendarLayer: String, CaseIterable, Identifiable, Sendable {
    case pnl = "盈亏"
    case market = "大盘"
    case temperature = "温度"

    var id: String { rawValue }

    var unitHint: String {
        switch self {
        case .pnl: "元(估算)"
        case .market: "日涨跌%"
        case .temperature: "0~100°"
        }
    }
}

enum GoldCalendarYearHeatmapMode: String, CaseIterable, Identifiable, Sendable {
    case pnl = "盈亏热力"
    case footprint = "攒金足迹"

    var id: String { rawValue }
}

enum GoldCalendarDayStatus: Equatable, Sendable {
    case trading
    case closed
    case noMarketData
    case future
}

enum GoldCalendarDirection: Equatable, Sendable {
    case up
    case down
    case flat

    static func from(_ value: Double?, epsilon: Double = 1e-6) -> GoldCalendarDirection {
        guard let value, value.isFinite else { return .flat }
        if value > epsilon { return .up }
        if value < -epsilon { return .down }
        return .flat
    }
}

/// 按当日涨跌幅 |Rate_D| 统一分 3 档低饱和热力（<0.5% → 8%，0.5%~1.5% → 16%，>=1.5% → 26%）。
enum GoldCalendarHeatLevel: Int, Equatable, Comparable, Sendable {
    case none = 0
    case mild = 1
    case medium = 2
    case strong = 3

    static func < (lhs: GoldCalendarHeatLevel, rhs: GoldCalendarHeatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(ratePercent: Double?) -> GoldCalendarHeatLevel {
        guard let ratePercent, ratePercent.isFinite else { return .none }
        let magnitude = abs(ratePercent)
        if magnitude < 1e-6 { return .none }
        if magnitude < 0.5 { return .mild }
        if magnitude < 1.5 { return .medium }
        return .strong
    }

    static func from(buyGrams: Double) -> GoldCalendarHeatLevel {
        guard buyGrams.isFinite, buyGrams > 1e-6 else { return .none }
        if buyGrams < 2 { return .mild }
        if buyGrams < 10 { return .medium }
        return .strong
    }

    var fillOpacity: Double {
        switch self {
        case .none: 0
        case .mild: 0.08
        case .medium: 0.16
        case .strong: 0.26
        }
    }
}

// MARK: - 稳定自然日键（彻底规避时区/夏令时键漂移）

struct CalendarDayKey: Hashable, Comparable, Sendable, Codable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    init?(isoDate: String) {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              (1...12).contains(m),
              (1...31).contains(d)
        else { return nil }
        self.year = y
        self.month = m
        self.day = d
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func noonDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    func addingDays(_ offset: Int, calendar: Calendar = .current) -> CalendarDayKey {
        let base = noonDate(calendar: calendar)
        let moved = calendar.date(byAdding: .day, value: offset, to: base) ?? base
        return CalendarDayKey(date: moved, calendar: calendar)
    }

    static func < (lhs: CalendarDayKey, rhs: CalendarDayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

// MARK: - 纯 Sendable 输入投影模型

struct CalendarHoldingItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let purchaseID: UUID
    let grams: Double
    let purity: Double
    let unitPriceCNY: Double
    let totalPurchaseCost: Double
    let extraFee: Double
    let laborFee: Double
    let timestamp: Date
    let disposition: String
    let disposedAt: Date?
    let disposalAmount: Double
    let bookName: String
    let brand: String
    let assetType: String
    let note: String
    let purchaseChannel: String
    let counterparty: String

    init(
        id: UUID = UUID(),
        purchaseID: UUID? = nil,
        grams: Double,
        purity: Double = 1,
        unitPriceCNY: Double,
        totalPurchaseCost: Double? = nil,
        extraFee: Double = 0,
        laborFee: Double = 0,
        timestamp: Date,
        disposition: String = "holding",
        disposedAt: Date? = nil,
        disposalAmount: Double = 0,
        bookName: String = "默认账本",
        brand: String = "",
        assetType: String = "其他",
        note: String = "",
        purchaseChannel: String = "",
        counterparty: String = ""
    ) {
        self.id = id
        self.purchaseID = purchaseID ?? id
        self.grams = grams.isFinite ? max(0, grams) : 0
        self.purity = purity.isFinite && purity > 0 && purity <= 1 ? purity : 1
        self.unitPriceCNY = unitPriceCNY.isFinite ? max(0, unitPriceCNY) : 0
        let fallbackCost = self.grams * self.unitPriceCNY + (laborFee.isFinite ? max(0, laborFee) : 0) + (extraFee.isFinite ? max(0, extraFee) : 0)
        if let totalPurchaseCost, totalPurchaseCost.isFinite, totalPurchaseCost >= 0 {
            self.totalPurchaseCost = totalPurchaseCost
        } else {
            self.totalPurchaseCost = fallbackCost
        }
        self.extraFee = extraFee.isFinite ? max(0, extraFee) : 0
        self.laborFee = laborFee.isFinite ? max(0, laborFee) : 0
        self.timestamp = timestamp
        self.disposition = disposition
        self.disposedAt = disposedAt
        self.disposalAmount = disposalAmount.isFinite ? max(0, disposalAmount) : 0
        self.bookName = bookName
        self.brand = brand
        self.assetType = assetType
        self.note = note
        self.purchaseChannel = purchaseChannel
        self.counterparty = counterparty
    }

    var effectiveGrams: Double {
        grams * purity
    }

    /// 买入裸金单价 P_buy：优先 unitPriceCNY，缺省时退回 totalPurchaseCost / grams。
    var bareUnitPriceCNY: Double {
        if unitPriceCNY.isFinite, unitPriceCNY > 0 {
            return unitPriceCNY
        }
        if grams > 0, totalPurchaseCost.isFinite, totalPurchaseCost > 0 {
            return totalPurchaseCost / grams
        }
        return 0
    }

    var displayTitle: String {
        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBrand.isEmpty { return trimmedBrand }
        let trimmedType = assetType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedType.isEmpty || trimmedType == "其他" ? "黄金记录" : trimmedType
    }

    var resolvedAssetType: GoldAssetType {
        GoldAssetType(rawValue: assetType) ?? .other
    }
}

extension HoldingRecord {
    var calendarItem: CalendarHoldingItem {
        CalendarHoldingItem(
            id: id,
            purchaseID: purchaseID ?? id,
            grams: grams,
            purity: purity,
            unitPriceCNY: unitPriceCNY,
            totalPurchaseCost: totalPurchaseCost,
            extraFee: extraFee,
            laborFee: laborFee,
            timestamp: timestamp,
            disposition: disposition,
            disposedAt: disposedAt,
            disposalAmount: disposalAmount,
            bookName: bookName,
            brand: brand,
            assetType: assetType,
            note: note,
            purchaseChannel: purchaseChannel,
            counterparty: counterparty
        )
    }
}

struct CalendarDailyMarketBar: Equatable, Sendable {
    let dayKey: CalendarDayKey
    let closeCNYPerGram: Double
    let openCNYPerGram: Double?
    let highCNYPerGram: Double?
    let lowCNYPerGram: Double?
    let prevCloseCNYPerGram: Double?
    let isLiveQuote: Bool

    init(
        dayKey: CalendarDayKey,
        closeCNYPerGram: Double,
        openCNYPerGram: Double? = nil,
        highCNYPerGram: Double? = nil,
        lowCNYPerGram: Double? = nil,
        prevCloseCNYPerGram: Double? = nil,
        isLiveQuote: Bool = false
    ) {
        self.dayKey = dayKey
        self.closeCNYPerGram = closeCNYPerGram
        self.openCNYPerGram = openCNYPerGram
        self.highCNYPerGram = highCNYPerGram
        self.lowCNYPerGram = lowCNYPerGram
        self.prevCloseCNYPerGram = prevCloseCNYPerGram
        self.isLiveQuote = isLiveQuote
    }
}

struct CalendarLiveQuoteInput: Equatable, Sendable {
    let cnyPerGram: Double
    let prevCloseCNYPerGram: Double?
    let usdCNY: Double?
    let asOf: Date

    init(cnyPerGram: Double, prevCloseCNYPerGram: Double? = nil, usdCNY: Double? = nil, asOf: Date) {
        self.cnyPerGram = cnyPerGram
        self.prevCloseCNYPerGram = prevCloseCNYPerGram
        self.usdCNY = usdCNY
        self.asOf = asOf
    }

    init?(quote: GoldQuote, basis: GoldMarketBasis) {
        guard let snap = MarketQuoteSnapshot.make(from: quote, basis: basis) else { return nil }
        self.cnyPerGram = snap.cnyPerGram
        self.prevCloseCNYPerGram = snap.prevCloseCNY
        self.usdCNY = snap.usdCNY
        self.asOf = snap.asOf
    }
}

struct CalendarTemperatureSample: Equatable, Sendable {
    let dayKey: CalendarDayKey
    let score: Double
    let level: MacroTemperatureLevel
}

// MARK: - 日 / 月 / 年输出快照

struct GoldCalendarDayEvent: Identifiable, Equatable, Sendable {
    let id: String
    let recordID: UUID
    let purchaseID: UUID
    let kind: String
    let grams: Double
    let unitPriceCNY: Double
    let totalCost: Double
    let proceeds: Double
    let title: String
    let assetType: GoldAssetType
    let bookName: String
    let date: Date
}

struct GoldCalendarDaySnapshot: Identifiable, Equatable, Sendable {
    let dayKey: CalendarDayKey
    let date: Date
    let status: GoldCalendarDayStatus
    let isToday: Bool

    let endOfDayHoldingGrams: Double
    let endOfDayEffectiveGrams: Double
    let referencePriceCNY: Double?
    let lastKnownPriceCNY: Double?
    let prevCloseCNY: Double?

    let marketChangeCNY: Double?
    let marketChangePercent: Double?

    let dailyPnL: Double?
    let dailyPnLRatePercent: Double?
    let dailyPnLBasis: Double
    let endOfDayValuationCNY: Double?

    let buyGrams: Double
    let buyCount: Int
    let soldGrams: Double
    let giftGrams: Double
    let events: [GoldCalendarDayEvent]
    let unlockedMilestones: [GoldMilestone]

    let temperatureScore: Double?
    let temperatureLevel: MacroTemperatureLevel?

    var id: CalendarDayKey { dayKey }

    var hasBuy: Bool { buyGrams > 1e-9 }
    var hasSold: Bool { soldGrams > 1e-9 }
    var hasGift: Bool { giftGrams > 1e-9 }
    var hasEvents: Bool { !events.isEmpty }
    var hasMilestone: Bool { !unlockedMilestones.isEmpty }

    var pnlDirection: GoldCalendarDirection {
        GoldCalendarDirection.from(dailyPnL)
    }

    var marketDirection: GoldCalendarDirection {
        GoldCalendarDirection.from(marketChangePercent)
    }

    var pnlHeatLevel: GoldCalendarHeatLevel {
        GoldCalendarHeatLevel.from(ratePercent: dailyPnLRatePercent)
    }

    var marketHeatLevel: GoldCalendarHeatLevel {
        GoldCalendarHeatLevel.from(ratePercent: marketChangePercent)
    }

    var footprintHeatLevel: GoldCalendarHeatLevel {
        GoldCalendarHeatLevel.from(buyGrams: buyGrams)
    }
}

struct GoldCalendarMonthSummary: Identifiable, Equatable, Sendable {
    let year: Int
    let month: Int
    let totalPnL: Double?
    let pnlRedDays: Int
    let pnlGreenDays: Int
    let pnlFlatDays: Int

    let marketMonthChangePercent: Double?
    let latestReferencePriceCNY: Double?
    let marketRedDays: Int
    let marketGreenDays: Int

    let newBuyGrams: Double
    let newBuyCount: Int
    let endOfMonthHoldingGrams: Double
    let unlockedMilestones: [GoldMilestone]

    var id: String { "\(year)-\(month)" }
    var hasAnyHoldingActivity: Bool {
        totalPnL != nil || newBuyGrams > 1e-9 || endOfMonthHoldingGrams > 1e-9
    }
}

struct GoldCalendarYearHeatCell: Identifiable, Equatable, Sendable {
    let dayKey: CalendarDayKey
    let inTargetYear: Bool
    let snapshot: GoldCalendarDaySnapshot?

    var id: CalendarDayKey { dayKey }
}

struct GoldCalendarYearSnapshot: Equatable, Sendable {
    let year: Int
    let todayKey: CalendarDayKey
    let totalPnL: Double?
    let pnlRedDays: Int
    let pnlGreenDays: Int
    let marketYearChangePercent: Double?
    let marketRedDays: Int
    let marketGreenDays: Int
    let totalBuyGrams: Double
    let totalBuyCount: Int
    let activeBuyDays: Int
    let monthSummaries: [GoldCalendarMonthSummary]
    let weeks: [[GoldCalendarYearHeatCell]]
    let daysByKey: [CalendarDayKey: GoldCalendarDaySnapshot]

    // 供 O(1) 今日实时增量补丁使用的锚点状态
    let startOfYearCarriedRawGrams: Double
    let startOfYearCarriedEffectiveGrams: Double
    let startOfYearLastKnownPrice: Double?
    let earliestMarketDay: CalendarDayKey?
    let yearOpenBaseClose: Double?
    let monthOpenBaseCloses: [Int: Double]

    func monthSummary(_ month: Int) -> GoldCalendarMonthSummary? {
        guard (1...12).contains(month), monthSummaries.count == 12 else { return nil }
        return monthSummaries[month - 1]
    }
}

struct GoldCalendarCompanionStats: Equatable, Sendable {
    let companionDays: Int
    let consecutiveActiveMonths: Int
    let currentHoldingGrams: Double
    let milestoneProgress: GoldMilestoneProgress
    let milestoneFirstReached: [CalendarDayKey: [GoldMilestone]]
    let hasAnyRecords: Bool
}

// MARK: - 核心 Sweep-Line 纯计算引擎（Sendable）

enum GoldCalendarEngine {
    static let troyOunceGrams = 31.1034768

    /// 按筛选条件过滤记录投影（与 HoldingCalendarFilter 语义保持一致）。
    static func filterItems(_ items: [CalendarHoldingItem], filter: HoldingCalendarFilter) -> [CalendarHoldingItem] {
        let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard item.grams > 0 else { return false }
            if let book = filter.book, item.bookName != book { return false }
            if !keyword.isEmpty {
                let matched = [item.brand, item.note, item.purchaseChannel, item.counterparty]
                    .contains { $0.localizedCaseInsensitiveContains(keyword) }
                if !matched { return false }
            }
            if filter.kind != "all" && item.disposition != filter.kind {
                return false
            }
            return true
        }
    }

    /// 将历史日线统一转换为 CNY/g 查表字典（国内原生 CNY/g；国际按当前汇率折算，缺失汇率时安全返回空表）。
    static func convertDailyBars(
        _ prices: [GoldDailyPrice],
        basis: GoldMarketBasis,
        usdCNY: Double?,
        calendar: Calendar = .current
    ) -> [CalendarDayKey: CalendarDailyMarketBar] {
        let factor: Double
        switch basis {
        case .domestic:
            factor = 1.0
        case .international:
            guard let usdCNY, usdCNY.isFinite, usdCNY > 0 else {
                return [:]
            }
            factor = usdCNY / troyOunceGrams
        }

        var map: [CalendarDayKey: CalendarDailyMarketBar] = [:]
        map.reserveCapacity(prices.count)
        for bar in prices {
            guard bar.close.isFinite, bar.close > 0 else { continue }
            let close = bar.close * factor
            guard close.isFinite, close > 0 else { continue }
            let open = bar.open.isFinite && bar.open > 0 ? bar.open * factor : nil
            let high = bar.high.isFinite && bar.high > 0 ? bar.high * factor : nil
            let low = bar.low.isFinite && bar.low > 0 ? bar.low * factor : nil
            let key = CalendarDayKey(date: bar.date, calendar: calendar)
            map[key] = CalendarDailyMarketBar(
                dayKey: key,
                closeCNYPerGram: close,
                openCNYPerGram: open,
                highCNYPerGram: high,
                lowCNYPerGram: low,
                prevCloseCNYPerGram: nil,
                isLiveQuote: false
            )
        }
        return map
    }

    static func temperatureMap(
        from points: [MacroTemperatureHistoryPoint],
        calendar: Calendar = .current
    ) -> [CalendarDayKey: CalendarTemperatureSample] {
        var result: [CalendarDayKey: CalendarTemperatureSample] = [:]
        result.reserveCapacity(points.count)
        for p in points {
            guard p.score.isFinite else { continue }
            let key = CalendarDayKey(isoDate: p.dateString) ?? CalendarDayKey(date: p.date, calendar: calendar)
            let clamped = min(max(p.score, 0), 100)
            result[key] = CalendarTemperatureSample(dayKey: key, score: clamped, level: p.level)
        }
        return result
    }

    /// 跨全量历史计算：陪伴天数、连续保持记录月数、当前在库克重、6 档里程碑首次达成日。
    static func computeCompanionStats(
        items: [CalendarHoldingItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoldCalendarCompanionStats {
        let validItems = items.filter { $0.grams > 0 }
        guard !validItems.isEmpty else {
            return GoldCalendarCompanionStats(
                companionDays: 0,
                consecutiveActiveMonths: 0,
                currentHoldingGrams: 0,
                milestoneProgress: .evaluate(totalGrams: 0),
                milestoneFirstReached: [:],
                hasAnyRecords: false
            )
        }

        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        var earliestBuyKey: CalendarDayKey?
        var buyMonths: Set<Int> = []
        var deltaByDay: [CalendarDayKey: Double] = [:]

        for item in validItems {
            let buyKey = CalendarDayKey(date: item.timestamp, calendar: calendar)
            if buyKey <= todayKey {
                if earliestBuyKey == nil || buyKey < earliestBuyKey! {
                    earliestBuyKey = buyKey
                }
                buyMonths.insert(buyKey.year * 12 + (buyKey.month - 1))
                deltaByDay[buyKey, default: 0] += item.grams
            }
            if (item.disposition == "sold" || item.disposition == "gift"),
               let disposedAt = item.disposedAt {
                let disposeKey = CalendarDayKey(date: disposedAt, calendar: calendar)
                if disposeKey <= todayKey {
                    deltaByDay[disposeKey, default: 0] -= item.grams
                }
            }
        }

        let companionDays: Int = {
            guard let earliestBuyKey else { return 0 }
            let start = earliestBuyKey.noonDate(calendar: calendar)
            let end = todayKey.noonDate(calendar: calendar)
            let diff = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            return max(1, diff + 1)
        }()

        // 客观连续记录月数：从本月（或本月尚未记账时从上月）往前连续计数，避免月初制造焦虑。
        let currentMonthIndex = todayKey.year * 12 + (todayKey.month - 1)
        var consecutiveMonths = 0
        var cursor = buyMonths.contains(currentMonthIndex) ? currentMonthIndex : (currentMonthIndex - 1)
        while buyMonths.contains(cursor) {
            consecutiveMonths += 1
            cursor -= 1
        }

        // 按自然日升序回放在库克重，定位每一档里程碑的首次达成日。
        let sortedDays = deltaByDay.keys.sorted()
        var runningGrams = 0.0
        var unlockedIDs: Set<String> = []
        var firstReached: [CalendarDayKey: [GoldMilestone]] = [:]

        for dayKey in sortedDays {
            runningGrams = sanitizeZero(runningGrams + (deltaByDay[dayKey] ?? 0))
            for tier in GoldMilestone.ladder {
                if !unlockedIDs.contains(tier.id), runningGrams + 1e-9 >= tier.targetGrams {
                    unlockedIDs.insert(tier.id)
                    firstReached[dayKey, default: []].append(tier)
                }
            }
        }

        let currentHolding = validItems
            .filter { $0.disposition == "holding" && CalendarDayKey(date: $0.timestamp, calendar: calendar) <= todayKey }
            .reduce(0.0) { $0 + $1.grams }

        return GoldCalendarCompanionStats(
            companionDays: companionDays,
            consecutiveActiveMonths: consecutiveMonths,
            currentHoldingGrams: currentHolding,
            milestoneProgress: .evaluate(totalGrams: currentHolding),
            milestoneFirstReached: firstReached,
            hasAnyRecords: true
        )
    }

    /// Sweep-Line O(D + N log N) 一次扫描生成全年每日快照、12 个月战报与 52 周热力矩阵。
    static func buildYearSnapshot(
        year: Int,
        items: [CalendarHoldingItem],
        dailyBars: [CalendarDayKey: CalendarDailyMarketBar],
        liveQuote: CalendarLiveQuoteInput?,
        temperatures: [CalendarDayKey: CalendarTemperatureSample],
        milestoneFirstReached: [CalendarDayKey: [GoldMilestone]],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoldCalendarYearSnapshot {
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        let yearStart = CalendarDayKey(year: year, month: 1, day: 1)
        let yearEnd = CalendarDayKey(year: year, month: 12, day: 31)

        // 合并今日实时报价（严格防周末误算：仅当 quote.asOf 落在今日自然日才将今日标为交易日）。
        var effectiveBars = dailyBars
        let liveQuoteAsOfKey = liveQuote.map { CalendarDayKey(date: $0.asOf, calendar: calendar) }
        if let liveQuote, liveQuote.cnyPerGram.isFinite, liveQuote.cnyPerGram > 0, liveQuoteAsOfKey == todayKey {
            effectiveBars[todayKey] = CalendarDailyMarketBar(
                dayKey: todayKey,
                closeCNYPerGram: liveQuote.cnyPerGram,
                openCNYPerGram: effectiveBars[todayKey]?.openCNYPerGram,
                highCNYPerGram: effectiveBars[todayKey]?.highCNYPerGram,
                lowCNYPerGram: effectiveBars[todayKey]?.lowCNYPerGram,
                prevCloseCNYPerGram: liveQuote.prevCloseCNYPerGram,
                isLiveQuote: true
            )
        }

        let sortedBarKeys = effectiveBars.keys.sorted()
        let earliestMarketDay = sortedBarKeys.first

        // 找到严格早于 yearStart 的最近交易日收盘价作为年初结转基准价。
        var lastKnownPrice: Double? = nil
        for key in sortedBarKeys where key < yearStart {
            lastKnownPrice = effectiveBars[key]?.closeCNYPerGram
        }
        let startOfYearLastKnownPrice = lastKnownPrice

        // 将全部持仓按买入日 / 处置日分组，同时累计年初前结转在库克重。
        var buysByDay: [CalendarDayKey: [CalendarHoldingItem]] = [:]
        var disposalsByDay: [CalendarDayKey: [CalendarHoldingItem]] = [:]
        var carriedRawGrams = 0.0
        var carriedEffectiveGrams = 0.0

        for item in items where item.grams > 0 {
            let buyKey = CalendarDayKey(date: item.timestamp, calendar: calendar)
            let disposeKey: CalendarDayKey? = (item.disposition == "sold" || item.disposition == "gift")
                ? item.disposedAt.map { CalendarDayKey(date: $0, calendar: calendar) }
                : nil

            if buyKey < yearStart && (disposeKey == nil || disposeKey! >= yearStart) {
                carriedRawGrams += item.grams
                carriedEffectiveGrams += item.effectiveGrams
            }
            if buyKey >= yearStart && buyKey <= yearEnd {
                buysByDay[buyKey, default: []].append(item)
            }
            if let disposeKey, disposeKey >= yearStart && disposeKey <= yearEnd {
                disposalsByDay[disposeKey, default: []].append(item)
            }
        }

        let startOfYearCarriedRawGrams = sanitizeZero(carriedRawGrams)
        let startOfYearCarriedEffectiveGrams = sanitizeZero(carriedEffectiveGrams)

        // 逐日 Sweep-Line 扫描 1月1日 ~ 12月31日。
        var daysByKey: [CalendarDayKey: GoldCalendarDaySnapshot] = [:]
        daysByKey.reserveCapacity(366)

        var monthOpenBaseCloses: [Int: Double] = [:]
        var monthLastTradingClose: [Int: Double] = [:]
        var monthLatestRefPrice: [Int: Double] = [:]
        var monthPnLSum: [Int: Double] = [:]
        var monthHasPnL: [Int: Bool] = [:]
        var monthPnLRed: [Int: Int] = [:]
        var monthPnLGreen: [Int: Int] = [:]
        var monthPnLFlat: [Int: Int] = [:]
        var monthMarketRed: [Int: Int] = [:]
        var monthMarketGreen: [Int: Int] = [:]
        var monthBuyGrams: [Int: Double] = [:]
        var monthBuyPurchaseIDs: [Int: Set<UUID>] = [:]
        var monthEndHoldingGrams: [Int: Double] = [:]
        var monthMilestones: [Int: [GoldMilestone]] = [:]

        var yearBuyPurchaseIDs: Set<UUID> = []
        var yearActiveBuyDays = 0
        var yearFirstTradingFallbackBase: Double? = nil
        var yearLastTradingClose: Double? = nil

        var cursor = yearStart
        while cursor <= yearEnd {
            let m = cursor.month
            if cursor.day == 1, let lastKnownPrice {
                monthOpenBaseCloses[m] = lastKnownPrice
            }

            let dayBuys = buysByDay[cursor] ?? []
            let dayDisposals = disposalsByDay[cursor] ?? []
            let bar = effectiveBars[cursor]
            let temp = temperatures[cursor]
            let milestones = milestoneFirstReached[cursor] ?? []

            let computed = evaluateDay(
                dayKey: cursor,
                todayKey: todayKey,
                carriedRawGrams: carriedRawGrams,
                carriedEffectiveGrams: carriedEffectiveGrams,
                dayBuys: dayBuys,
                dayDisposals: dayDisposals,
                bar: bar,
                lastKnownPriceBeforeDay: lastKnownPrice,
                earliestMarketDay: earliestMarketDay,
                liveQuoteFallbackForClosedToday: (cursor == todayKey && liveQuoteAsOfKey != todayKey) ? liveQuote?.cnyPerGram : nil,
                temperature: temp,
                unlockedMilestones: milestones,
                calendar: calendar
            )

            daysByKey[cursor] = computed.snapshot
            carriedRawGrams = computed.nextCarriedRawGrams
            carriedEffectiveGrams = computed.nextCarriedEffectiveGrams
            if let close = computed.snapshot.referencePriceCNY, computed.snapshot.status == .trading {
                lastKnownPrice = close
                monthLastTradingClose[m] = close
                yearLastTradingClose = close
                if monthOpenBaseCloses[m] == nil {
                    monthOpenBaseCloses[m] = computed.snapshot.prevCloseCNY ?? bar?.openCNYPerGram ?? close
                }
                if yearFirstTradingFallbackBase == nil {
                    yearFirstTradingFallbackBase = computed.snapshot.prevCloseCNY ?? bar?.openCNYPerGram ?? close
                }
            }
            if let ref = computed.snapshot.lastKnownPriceCNY, computed.snapshot.status != .future {
                monthLatestRefPrice[m] = ref
            }

            if computed.snapshot.status != .future {
                monthEndHoldingGrams[m] = computed.snapshot.endOfDayHoldingGrams
            }
            if computed.snapshot.status == .trading {
                if let pnl = computed.snapshot.dailyPnL {
                    monthHasPnL[m] = true
                    monthPnLSum[m, default: 0] += pnl
                    switch computed.snapshot.pnlDirection {
                    case .up: monthPnLRed[m, default: 0] += 1
                    case .down: monthPnLGreen[m, default: 0] += 1
                    case .flat: monthPnLFlat[m, default: 0] += 1
                    }
                }
                switch computed.snapshot.marketDirection {
                case .up: monthMarketRed[m, default: 0] += 1
                case .down: monthMarketGreen[m, default: 0] += 1
                case .flat: break
                }
            }
            if computed.snapshot.buyGrams > 1e-9 {
                monthBuyGrams[m, default: 0] += computed.snapshot.buyGrams
                yearActiveBuyDays += 1
                for item in dayBuys {
                    monthBuyPurchaseIDs[m, default: []].insert(item.purchaseID)
                    yearBuyPurchaseIDs.insert(item.purchaseID)
                }
            }
            if !milestones.isEmpty {
                monthMilestones[m, default: []].append(contentsOf: milestones)
            }

            cursor = cursor.addingDays(1, calendar: calendar)
        }

        // 汇总 12 个月战报（逐日盈亏之和 == 月战报总额）。
        var monthSummaries: [GoldCalendarMonthSummary] = []
        monthSummaries.reserveCapacity(12)
        var yearTotalPnL: Double? = nil
        var yearPnLRed = 0
        var yearPnLGreen = 0
        var yearMarketRed = 0
        var yearMarketGreen = 0
        var yearTotalBuyGrams = 0.0

        for m in 1...12 {
            let mPnL: Double? = monthHasPnL[m] == true ? (monthPnLSum[m] ?? 0) : nil
            let mRed = monthPnLRed[m] ?? 0
            let mGreen = monthPnLGreen[m] ?? 0
            let mFlat = monthPnLFlat[m] ?? 0
            let mkRed = monthMarketRed[m] ?? 0
            let mkGreen = monthMarketGreen[m] ?? 0
            let mBuyGrams = monthBuyGrams[m] ?? 0
            let mBuyCount = monthBuyPurchaseIDs[m]?.count ?? 0

            let mMarketPct: Double? = {
                guard let endClose = monthLastTradingClose[m],
                      let base = monthOpenBaseCloses[m],
                      base > 0 else { return nil }
                return (endClose - base) / base * 100
            }()

            if let mPnL {
                yearTotalPnL = (yearTotalPnL ?? 0) + mPnL
            }
            yearPnLRed += mRed
            yearPnLGreen += mGreen
            yearMarketRed += mkRed
            yearMarketGreen += mkGreen
            yearTotalBuyGrams += mBuyGrams

            monthSummaries.append(
                GoldCalendarMonthSummary(
                    year: year,
                    month: m,
                    totalPnL: mPnL,
                    pnlRedDays: mRed,
                    pnlGreenDays: mGreen,
                    pnlFlatDays: mFlat,
                    marketMonthChangePercent: mMarketPct,
                    latestReferencePriceCNY: monthLastTradingClose[m] ?? monthLatestRefPrice[m],
                    marketRedDays: mkRed,
                    marketGreenDays: mkGreen,
                    newBuyGrams: mBuyGrams,
                    newBuyCount: mBuyCount,
                    endOfMonthHoldingGrams: monthEndHoldingGrams[m] ?? 0,
                    unlockedMilestones: monthMilestones[m] ?? []
                )
            )
        }

        let yearOpenBaseClose = startOfYearLastKnownPrice ?? yearFirstTradingFallbackBase
        let marketYearChangePercent: Double? = {
            guard let endClose = yearLastTradingClose,
                  let base = yearOpenBaseClose,
                  base > 0 else { return nil }
            return (endClose - base) / base * 100
        }()

        let weeks = buildYearHeatmapWeeks(year: year, daysByKey: daysByKey, calendar: calendar)

        return GoldCalendarYearSnapshot(
            year: year,
            todayKey: todayKey,
            totalPnL: yearTotalPnL,
            pnlRedDays: yearPnLRed,
            pnlGreenDays: yearPnLGreen,
            marketYearChangePercent: marketYearChangePercent,
            marketRedDays: yearMarketRed,
            marketGreenDays: yearMarketGreen,
            totalBuyGrams: yearTotalBuyGrams,
            totalBuyCount: yearBuyPurchaseIDs.count,
            activeBuyDays: yearActiveBuyDays,
            monthSummaries: monthSummaries,
            weeks: weeks,
            daysByKey: daysByKey,
            startOfYearCarriedRawGrams: startOfYearCarriedRawGrams,
            startOfYearCarriedEffectiveGrams: startOfYearCarriedEffectiveGrams,
            startOfYearLastKnownPrice: startOfYearLastKnownPrice,
            earliestMarketDay: earliestMarketDay,
            yearOpenBaseClose: yearOpenBaseClose,
            monthOpenBaseCloses: monthOpenBaseCloses
        )
    }

    /// 5 秒实时报价到达时，O(1) 增量更新「今天」一格、当月战报与当年合计，绝不重算全年 365 天。
    static func patchToday(
        in snapshot: GoldCalendarYearSnapshot,
        items: [CalendarHoldingItem],
        dailyBars: [CalendarDayKey: CalendarDailyMarketBar],
        liveQuote: CalendarLiveQuoteInput?,
        temperature: CalendarTemperatureSample?,
        unlockedMilestones: [GoldMilestone],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoldCalendarYearSnapshot {
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        guard snapshot.year == todayKey.year,
              let oldToday = snapshot.daysByKey[todayKey] else {
            return snapshot
        }

        let carriedRawGrams: Double
        let carriedEffectiveGrams: Double
        let lastKnownPriceBeforeDay: Double?

        if todayKey.month == 1 && todayKey.day == 1 {
            carriedRawGrams = snapshot.startOfYearCarriedRawGrams
            carriedEffectiveGrams = snapshot.startOfYearCarriedEffectiveGrams
            lastKnownPriceBeforeDay = snapshot.startOfYearLastKnownPrice
        } else {
            let yesterdayKey = todayKey.addingDays(-1, calendar: calendar)
            let yesterday = snapshot.daysByKey[yesterdayKey]
            carriedRawGrams = yesterday?.endOfDayHoldingGrams ?? 0
            carriedEffectiveGrams = yesterday?.endOfDayEffectiveGrams ?? 0
            lastKnownPriceBeforeDay = yesterday?.lastKnownPriceCNY ?? snapshot.startOfYearLastKnownPrice
        }

        let liveQuoteAsOfKey = liveQuote.map { CalendarDayKey(date: $0.asOf, calendar: calendar) }
        var barForToday = dailyBars[todayKey]
        if let liveQuote, liveQuote.cnyPerGram.isFinite, liveQuote.cnyPerGram > 0, liveQuoteAsOfKey == todayKey {
            barForToday = CalendarDailyMarketBar(
                dayKey: todayKey,
                closeCNYPerGram: liveQuote.cnyPerGram,
                openCNYPerGram: barForToday?.openCNYPerGram,
                highCNYPerGram: barForToday?.highCNYPerGram,
                lowCNYPerGram: barForToday?.lowCNYPerGram,
                prevCloseCNYPerGram: liveQuote.prevCloseCNYPerGram,
                isLiveQuote: true
            )
        }

        let dayBuys = items.filter { $0.grams > 0 && CalendarDayKey(date: $0.timestamp, calendar: calendar) == todayKey }
        let dayDisposals = items.filter {
            $0.grams > 0 && ($0.disposition == "sold" || $0.disposition == "gift")
                && $0.disposedAt.map { CalendarDayKey(date: $0, calendar: calendar) == todayKey } == true
        }

        let earliestMarketDay: CalendarDayKey? = {
            if let existing = snapshot.earliestMarketDay {
                if let bar = barForToday, bar.dayKey < existing { return bar.dayKey }
                return existing
            }
            return barForToday?.dayKey
        }()

        let evaluated = evaluateDay(
            dayKey: todayKey,
            todayKey: todayKey,
            carriedRawGrams: carriedRawGrams,
            carriedEffectiveGrams: carriedEffectiveGrams,
            dayBuys: dayBuys,
            dayDisposals: dayDisposals,
            bar: barForToday,
            lastKnownPriceBeforeDay: lastKnownPriceBeforeDay,
            earliestMarketDay: earliestMarketDay,
            liveQuoteFallbackForClosedToday: liveQuoteAsOfKey != todayKey ? liveQuote?.cnyPerGram : nil,
            temperature: temperature,
            unlockedMilestones: unlockedMilestones,
            calendar: calendar
        )
        let newToday = evaluated.snapshot
        if newToday == oldToday {
            return snapshot
        }

        var updatedDays = snapshot.daysByKey
        updatedDays[todayKey] = newToday

        // O(1) 定位今天在 52 周矩阵中的位置（不遍历整表）。
        var updatedWeeks = snapshot.weeks
        let jan1 = CalendarDayKey(year: snapshot.year, month: 1, day: 1)
        let jan1Weekday = calendar.component(.weekday, from: jan1.noonDate(calendar: calendar)) // 1=Sun...7=Sat
        let gridStart = jan1.addingDays(-(jan1Weekday - 1), calendar: calendar)
        let dayOffset = calendar.dateComponents([.day], from: gridStart.noonDate(calendar: calendar), to: todayKey.noonDate(calendar: calendar)).day ?? -1
        if dayOffset >= 0 {
            let col = dayOffset / 7
            let row = dayOffset % 7
            if col < updatedWeeks.count, row < updatedWeeks[col].count, updatedWeeks[col][row].dayKey == todayKey {
                updatedWeeks[col][row] = GoldCalendarYearHeatCell(dayKey: todayKey, inTargetYear: true, snapshot: newToday)
            }
        }

        // O(1) 差量更新当月战报与当年合计。
        let oldHasPnL = oldToday.status == .trading && oldToday.dailyPnL != nil
        let newHasPnL = newToday.status == .trading && newToday.dailyPnL != nil
        let oldPnLVal = oldHasPnL ? (oldToday.dailyPnL ?? 0) : 0
        let newPnLVal = newHasPnL ? (newToday.dailyPnL ?? 0) : 0
        let pnlDelta = newPnLVal - oldPnLVal

        let oldPnLRed = (oldHasPnL && oldToday.pnlDirection == .up) ? 1 : 0
        let newPnLRed = (newHasPnL && newToday.pnlDirection == .up) ? 1 : 0
        let oldPnLGreen = (oldHasPnL && oldToday.pnlDirection == .down) ? 1 : 0
        let newPnLGreen = (newHasPnL && newToday.pnlDirection == .down) ? 1 : 0
        let oldPnLFlat = (oldHasPnL && oldToday.pnlDirection == .flat) ? 1 : 0
        let newPnLFlat = (newHasPnL && newToday.pnlDirection == .flat) ? 1 : 0

        let oldMkRed = (oldToday.status == .trading && oldToday.marketDirection == .up) ? 1 : 0
        let newMkRed = (newToday.status == .trading && newToday.marketDirection == .up) ? 1 : 0
        let oldMkGreen = (oldToday.status == .trading && oldToday.marketDirection == .down) ? 1 : 0
        let newMkGreen = (newToday.status == .trading && newToday.marketDirection == .down) ? 1 : 0

        var updatedMonths = snapshot.monthSummaries
        let monthIndex = todayKey.month - 1
        var updatedMonthOpenBases = snapshot.monthOpenBaseCloses
        var updatedYearOpenBase = snapshot.yearOpenBaseClose

        if monthIndex >= 0 && monthIndex < updatedMonths.count {
            let oldMonth = updatedMonths[monthIndex]
            let mRed = oldMonth.pnlRedDays - oldPnLRed + newPnLRed
            let mGreen = oldMonth.pnlGreenDays - oldPnLGreen + newPnLGreen
            let mFlat = oldMonth.pnlFlatDays - oldPnLFlat + newPnLFlat
            let mHasAnyPnL = (mRed + mGreen + mFlat) > 0
            let mTotalPnL: Double? = mHasAnyPnL ? ((oldMonth.totalPnL ?? 0) + pnlDelta) : nil

            if updatedMonthOpenBases[todayKey.month] == nil, newToday.status == .trading, let close = newToday.referencePriceCNY {
                updatedMonthOpenBases[todayKey.month] = newToday.prevCloseCNY ?? barForToday?.openCNYPerGram ?? close
            }
            if updatedYearOpenBase == nil, newToday.status == .trading, let close = newToday.referencePriceCNY {
                updatedYearOpenBase = newToday.prevCloseCNY ?? barForToday?.openCNYPerGram ?? close
            }

            let latestCloseForMonth = (newToday.status == .trading ? newToday.referencePriceCNY : nil) ?? lastKnownPriceBeforeDay
            let mMarketPct: Double? = {
                if newToday.status == .trading, let endClose = newToday.referencePriceCNY,
                   let base = updatedMonthOpenBases[todayKey.month], base > 0 {
                    return (endClose - base) / base * 100
                }
                return oldMonth.marketMonthChangePercent
            }()

            updatedMonths[monthIndex] = GoldCalendarMonthSummary(
                year: oldMonth.year,
                month: oldMonth.month,
                totalPnL: mTotalPnL,
                pnlRedDays: mRed,
                pnlGreenDays: mGreen,
                pnlFlatDays: mFlat,
                marketMonthChangePercent: mMarketPct,
                latestReferencePriceCNY: latestCloseForMonth ?? newToday.lastKnownPriceCNY ?? oldMonth.latestReferencePriceCNY,
                marketRedDays: oldMonth.marketRedDays - oldMkRed + newMkRed,
                marketGreenDays: oldMonth.marketGreenDays - oldMkGreen + newMkGreen,
                newBuyGrams: oldMonth.newBuyGrams,
                newBuyCount: oldMonth.newBuyCount,
                endOfMonthHoldingGrams: newToday.endOfDayHoldingGrams,
                unlockedMilestones: oldMonth.unlockedMilestones
            )
        }

        let yRed = snapshot.pnlRedDays - oldPnLRed + newPnLRed
        let yGreen = snapshot.pnlGreenDays - oldPnLGreen + newPnLGreen
        let yHasAnyPnL = updatedMonths.contains { $0.totalPnL != nil }
        let yTotalPnL: Double? = yHasAnyPnL ? ((snapshot.totalPnL ?? 0) + pnlDelta) : nil

        let yMarketPct: Double? = {
            if newToday.status == .trading, let endClose = newToday.referencePriceCNY,
               let base = updatedYearOpenBase, base > 0 {
                return (endClose - base) / base * 100
            }
            return snapshot.marketYearChangePercent
        }()

        return GoldCalendarYearSnapshot(
            year: snapshot.year,
            todayKey: todayKey,
            totalPnL: yTotalPnL,
            pnlRedDays: yRed,
            pnlGreenDays: yGreen,
            marketYearChangePercent: yMarketPct,
            marketRedDays: snapshot.marketRedDays - oldMkRed + newMkRed,
            marketGreenDays: snapshot.marketGreenDays - oldMkGreen + newMkGreen,
            totalBuyGrams: snapshot.totalBuyGrams,
            totalBuyCount: snapshot.totalBuyCount,
            activeBuyDays: snapshot.activeBuyDays,
            monthSummaries: updatedMonths,
            weeks: updatedWeeks,
            daysByKey: updatedDays,
            startOfYearCarriedRawGrams: snapshot.startOfYearCarriedRawGrams,
            startOfYearCarriedEffectiveGrams: snapshot.startOfYearCarriedEffectiveGrams,
            startOfYearLastKnownPrice: snapshot.startOfYearLastKnownPrice,
            earliestMarketDay: earliestMarketDay,
            yearOpenBaseClose: updatedYearOpenBase,
            monthOpenBaseCloses: updatedMonthOpenBases
        )
    }

    // MARK: - 单日防失真公式核心（Δ1 ~ Δ4 + 赠送恒记 0）

    private struct DayEvaluationOutput {
        let snapshot: GoldCalendarDaySnapshot
        let nextCarriedRawGrams: Double
        let nextCarriedEffectiveGrams: Double
    }

    private static func evaluateDay(
        dayKey: CalendarDayKey,
        todayKey: CalendarDayKey,
        carriedRawGrams: Double,
        carriedEffectiveGrams: Double,
        dayBuys: [CalendarHoldingItem],
        dayDisposals: [CalendarHoldingItem],
        bar: CalendarDailyMarketBar?,
        lastKnownPriceBeforeDay: Double?,
        earliestMarketDay: CalendarDayKey?,
        liveQuoteFallbackForClosedToday: Double?,
        temperature: CalendarTemperatureSample?,
        unlockedMilestones: [GoldMilestone],
        calendar: Calendar
    ) -> DayEvaluationOutput {
        let isToday = (dayKey == todayKey)
        let noon = dayKey.noonDate(calendar: calendar)

        // 区分当日四类交易集合
        var carriedSold: [CalendarHoldingItem] = []
        var carriedGift: [CalendarHoldingItem] = []
        var sameDaySold: [CalendarHoldingItem] = []
        var sameDayGift: [CalendarHoldingItem] = []
        var disposedTodayIDs: Set<UUID> = []

        for item in dayDisposals {
            disposedTodayIDs.insert(item.id)
            let buyKey = CalendarDayKey(date: item.timestamp, calendar: calendar)
            let isSameDay = (buyKey == dayKey)
            if item.disposition == "sold" {
                if isSameDay { sameDaySold.append(item) } else { carriedSold.append(item) }
            } else if item.disposition == "gift" {
                if isSameDay { sameDayGift.append(item) } else { carriedGift.append(item) }
            }
        }

        let boughtAndHeld = dayBuys.filter { !disposedTodayIDs.contains($0.id) }

        // 当日流水明细与统计
        var events: [GoldCalendarDayEvent] = []
        var buyGrams = 0.0
        var buyPurchaseIDs: Set<UUID> = []
        var soldGrams = 0.0
        var giftGrams = 0.0

        for item in dayBuys {
            buyGrams += item.grams
            buyPurchaseIDs.insert(item.purchaseID)
            events.append(
                GoldCalendarDayEvent(
                    id: "buy-\(item.id.uuidString)",
                    recordID: item.id,
                    purchaseID: item.purchaseID,
                    kind: "buy",
                    grams: item.grams,
                    unitPriceCNY: item.bareUnitPriceCNY,
                    totalCost: item.totalPurchaseCost,
                    proceeds: 0,
                    title: item.displayTitle,
                    assetType: item.resolvedAssetType,
                    bookName: item.bookName,
                    date: item.timestamp
                )
            )
        }

        for item in dayDisposals {
            if item.disposition == "sold" { soldGrams += item.grams }
            if item.disposition == "gift" { giftGrams += item.grams }
            events.append(
                GoldCalendarDayEvent(
                    id: "dispose-\(item.id.uuidString)",
                    recordID: item.id,
                    purchaseID: item.purchaseID,
                    kind: item.disposition,
                    grams: item.grams,
                    unitPriceCNY: item.bareUnitPriceCNY,
                    totalCost: item.totalPurchaseCost,
                    proceeds: item.disposalAmount,
                    title: item.displayTitle,
                    assetType: item.resolvedAssetType,
                    bookName: item.bookName,
                    date: item.disposedAt ?? noon
                )
            )
        }
        events.sort { $0.date > $1.date }

        // 收盘在库克重（无论休市/交易日均推进 Sweep-Line，保证后续交易日结转准确）。
        let addedRaw = boughtAndHeld.reduce(0.0) { $0 + $1.grams }
        let addedEff = boughtAndHeld.reduce(0.0) { $0 + $1.effectiveGrams }
        let removedCarriedRaw = carriedSold.reduce(0.0) { $0 + $1.grams } + carriedGift.reduce(0.0) { $0 + $1.grams }
        let removedCarriedEff = carriedSold.reduce(0.0) { $0 + $1.effectiveGrams } + carriedGift.reduce(0.0) { $0 + $1.effectiveGrams }

        let nextCarriedRaw = sanitizeZero(carriedRawGrams + addedRaw - removedCarriedRaw)
        let nextCarriedEff = sanitizeZero(carriedEffectiveGrams + addedEff - removedCarriedEff)

        // 判定自然日状态
        let status: GoldCalendarDayStatus
        if dayKey > todayKey {
            status = .future
        } else if let bar, bar.closeCNYPerGram.isFinite, bar.closeCNYPerGram > 0 {
            status = .trading
        } else if let earliestMarketDay, dayKey < earliestMarketDay {
            status = .noMarketData
        } else if earliestMarketDay == nil {
            status = .noMarketData
        } else {
            status = .closed
        }

        let prevClose: Double? = {
            guard status != .future else { return nil }
            if let lastKnownPriceBeforeDay, lastKnownPriceBeforeDay.isFinite, lastKnownPriceBeforeDay > 0 {
                return lastKnownPriceBeforeDay
            }
            if let barPrev = bar?.prevCloseCNYPerGram, barPrev.isFinite, barPrev > 0 {
                return barPrev
            }
            return nil
        }()

        let referencePrice: Double? = (status == .trading) ? bar?.closeCNYPerGram : nil
        let lastKnownPrice: Double? = {
            if let referencePrice { return referencePrice }
            if status == .future || status == .noMarketData { return nil }
            if let lastKnownPriceBeforeDay { return lastKnownPriceBeforeDay }
            if let fallback = liveQuoteFallbackForClosedToday, fallback.isFinite, fallback > 0 { return fallback }
            return nil
        }()

        let marketChangeCNY: Double? = {
            guard status == .trading, let pD = referencePrice, let pPrev = prevClose, pPrev > 0 else { return nil }
            return pD - pPrev
        }()
        let marketChangePercent: Double? = {
            guard let delta = marketChangeCNY, let pPrev = prevClose, pPrev > 0 else { return nil }
            return delta / pPrev * 100
        }()

        // 防失真单日持仓盈亏 Δ1 ~ Δ4 + 赠送恒记 0
        var dailyPnL: Double? = nil
        var dailyBasis = 0.0

        if status == .trading, let pD = referencePrice, pD > 0 {
            let carriedStillHeldEff = sanitizeZero(carriedEffectiveGrams - removedCarriedEff)
            var sumPnL = 0.0
            var hasPnLComponent = false

            // Δ1: 昨日结转、今日收盘仍在库
            if carriedStillHeldEff > 1e-9, let pPrev = prevClose, pPrev > 0 {
                sumPnL += carriedStillHeldEff * (pD - pPrev)
                dailyBasis += carriedStillHeldEff * pPrev
                hasPnLComponent = true
            }

            // Δ2: 今日新买入、今日收盘仍在库（隔离本金与工费，仅算裸金单价到当日收盘波动）
            for item in boughtAndHeld {
                let pBuy = item.bareUnitPriceCNY
                guard pBuy > 0 else { continue }
                let gEff = item.effectiveGrams
                sumPnL += gEff * (pD - pBuy)
                dailyBasis += gEff * pBuy
                hasPnLComponent = true
            }

            // Δ3: 昨日结转、今日卖出
            if !carriedSold.isEmpty, let pPrev = prevClose, pPrev > 0 {
                for item in carriedSold {
                    let gEff = item.effectiveGrams
                    sumPnL += item.disposalAmount - gEff * pPrev
                    dailyBasis += gEff * pPrev
                    hasPnLComponent = true
                }
            }

            // Δ4: 同日买入且同日卖出
            for item in sameDaySold {
                let pBuy = item.bareUnitPriceCNY
                guard pBuy > 0 else { continue }
                sumPnL += item.disposalAmount - item.grams * pBuy
                dailyBasis += item.effectiveGrams * pBuy
                hasPnLComponent = true
            }

            // 5. 今日赠出（无论何时买入）：恒记 0，不误算亏损
            let hasGiftOnly = !hasPnLComponent && (!carriedGift.isEmpty || !sameDayGift.isEmpty)
            if hasPnLComponent {
                dailyPnL = abs(sumPnL) < 1e-9 ? 0 : sumPnL
            } else if hasGiftOnly {
                dailyPnL = 0
            }
        }

        let dailyPnLRatePercent: Double? = {
            guard let dailyPnL, dailyBasis > 1e-9 else { return nil }
            let rate = dailyPnL / dailyBasis * 100
            return rate.isFinite ? rate : nil
        }()

        let endOfDayValuationCNY: Double? = {
            guard status != .future, nextCarriedEff > 1e-9, let price = lastKnownPrice, price > 0 else { return nil }
            return nextCarriedEff * price
        }()

        let snapshot = GoldCalendarDaySnapshot(
            dayKey: dayKey,
            date: noon,
            status: status,
            isToday: isToday,
            endOfDayHoldingGrams: status == .future ? 0 : nextCarriedRaw,
            endOfDayEffectiveGrams: status == .future ? 0 : nextCarriedEff,
            referencePriceCNY: referencePrice,
            lastKnownPriceCNY: lastKnownPrice,
            prevCloseCNY: prevClose,
            marketChangeCNY: marketChangeCNY,
            marketChangePercent: marketChangePercent,
            dailyPnL: dailyPnL,
            dailyPnLRatePercent: dailyPnLRatePercent,
            dailyPnLBasis: dailyBasis,
            endOfDayValuationCNY: endOfDayValuationCNY,
            buyGrams: buyGrams,
            buyCount: buyPurchaseIDs.count,
            soldGrams: soldGrams,
            giftGrams: giftGrams,
            events: events,
            unlockedMilestones: unlockedMilestones,
            temperatureScore: status == .future ? nil : temperature?.score,
            temperatureLevel: status == .future ? nil : temperature?.level
        )

        return DayEvaluationOutput(
            snapshot: snapshot,
            nextCarriedRawGrams: nextCarriedRaw,
            nextCarriedEffectiveGrams: nextCarriedEff
        )
    }

    private static func buildYearHeatmapWeeks(
        year: Int,
        daysByKey: [CalendarDayKey: GoldCalendarDaySnapshot],
        calendar: Calendar
    ) -> [[GoldCalendarYearHeatCell]] {
        let jan1 = CalendarDayKey(year: year, month: 1, day: 1)
        let dec31 = CalendarDayKey(year: year, month: 12, day: 31)
        let jan1Weekday = calendar.component(.weekday, from: jan1.noonDate(calendar: calendar)) // 1=Sun...7=Sat
        let dec31Weekday = calendar.component(.weekday, from: dec31.noonDate(calendar: calendar))

        let gridStart = jan1.addingDays(-(jan1Weekday - 1), calendar: calendar)
        let gridEnd = dec31.addingDays(7 - dec31Weekday, calendar: calendar)

        var weeks: [[GoldCalendarYearHeatCell]] = []
        var currentWeek: [GoldCalendarYearHeatCell] = []
        currentWeek.reserveCapacity(7)

        var cursor = gridStart
        while cursor <= gridEnd {
            let inYear = cursor.year == year
            let cell = GoldCalendarYearHeatCell(
                dayKey: cursor,
                inTargetYear: inYear,
                snapshot: inYear ? daysByKey[cursor] : nil
            )
            currentWeek.append(cell)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
                currentWeek.reserveCapacity(7)
            }
            cursor = cursor.addingDays(1, calendar: calendar)
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }
        return weeks
    }

    private static func sanitizeZero(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return value < 1e-9 ? 0 : value
    }
}

// MARK: - 格式化与纯客观合规文案（脱敏一致、零投顾词）

enum GoldCalendarFormat {
    /// 月历 62pt 紧凑格内盈亏文本：隐私模式下不铺满 `••`，仅保留极轻 `+`/`-` 方向符号。
    static func compactCellPnL(_ value: Double?, hideAmounts: Bool) -> String {
        guard let value, value.isFinite else { return "" }
        if hideAmounts {
            switch GoldCalendarDirection.from(value) {
            case .up: return "+"
            case .down: return "-"
            case .flat: return ""
            }
        }
        let absVal = abs(value)
        let sign = value > 1e-6 ? "+" : value < -1e-6 ? "-" : ""
        if absVal < 0.05 { return "0" }
        if absVal < 10 {
            return "\(sign)\(String(format: "%.1f", absVal))"
        }
        if absVal < 1_000 {
            return "\(sign)\(Int(absVal.rounded()))"
        }
        if absVal < 100_000 {
            return "\(sign)\(String(format: "%.1f", absVal / 1_000))k"
        }
        return "\(sign)\(String(format: "%.1f", absVal / 10_000))万"
    }

    /// 月历格内大盘日涨跌幅（公开市场数据，不受 hideAmounts 隐藏）。
    static func compactCellPercent(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "" }
        let sign = percent > 1e-6 ? "+" : percent < -1e-6 ? "-" : ""
        let absVal = abs(percent)
        if absVal < 0.05 { return "0.0%" }
        return "\(sign)\(String(format: "%.1f", absVal))%"
    }

    /// 月历格内温度分值（公开市场数据，不受 hideAmounts 隐藏）。
    static func compactCellTemperature(_ score: Double?) -> String {
        guard let score, score.isFinite else { return "" }
        let clamped = min(max(score, 0), 100)
        return "\(Int(clamped.rounded()))°"
    }

    static func signedCurrency(_ value: Double?, hideAmounts: Bool) -> String {
        if hideAmounts { return "••••" }
        guard let value, value.isFinite else { return "—" }
        let sign = value > 1e-6 ? "+" : value < -1e-6 ? "-" : ""
        return "\(sign)¥\(abs(value).moneyText)"
    }

    static func currency(_ value: Double?, hideAmounts: Bool) -> String {
        if hideAmounts { return "••••" }
        guard let value, value.isFinite else { return "—" }
        return "¥\(value.moneyText)"
    }

    static func signedPercent(_ value: Double?, hideAmounts: Bool = false) -> String {
        if hideAmounts { return "••••" }
        guard let value, value.isFinite else { return "—" }
        let sign = value > 1e-6 ? "+" : value < -1e-6 ? "-" : ""
        return "\(sign)\(String(format: "%.2f", abs(value)))%"
    }

    static func headerCompanionBadge(companionDays: Int, hasRecords: Bool) -> String {
        guard hasRecords, companionDays > 0 else { return "大盘观察中" }
        return "陪伴第 \(companionDays) 天"
    }

    /// 月度战报卡底部单行客观陪伴彩蛋（100% 纯客观、零焦虑、零投顾词）。
    static func monthCompanionBanner(
        monthSummary: GoldCalendarMonthSummary,
        companion: GoldCalendarCompanionStats,
        hideAmounts: Bool
    ) -> String? {
        guard companion.hasAnyRecords else { return nil }
        if hideAmounts {
            return "隐私模式已开启 · 已隐藏金额与克重"
        }
        if let milestone = monthSummary.unlockedMilestones.last {
            return "本月点亮「\(milestone.title)」"
        }
        if companion.consecutiveActiveMonths >= 2 {
            return "已连续 \(companion.consecutiveActiveMonths) 个月保持记录"
        }
        if companion.currentHoldingGrams > 1e-9 {
            if let next = companion.milestoneProgress.next {
                return "距「\(next.title)」还差 \(GoldVaultSummary.formatGrams(companion.milestoneProgress.remainingToNext))g"
            }
            return "已点亮全部 6 档里程碑"
        }
        return nil
    }

    /// 当日无操作时的克制客观文案（替代原大面积 ContentUnavailableView）。
    static func emptyDayJournalNote(snapshot: GoldCalendarDaySnapshot, hideAmounts: Bool) -> String {
        if snapshot.endOfDayHoldingGrams > 1e-9 {
            if hideAmounts {
                return "当天静静持有 •••• g，当日无新增记录"
            }
            return "当天静静持有 \(GoldVaultSummary.formatGrams(snapshot.endOfDayHoldingGrams))g，当日无新增记录"
        }
        return "当天暂无记金记录，可随时补记历史黄金"
    }

    static func basisFootnote(basis: GoldMarketBasis) -> String {
        switch basis {
        case .domestic:
            "预估盈亏按当日与前交易日参考收盘价测算，仅作客观记录参考。"
        case .international:
            "国际口径历史单价按当前汇率折算参考，预估盈亏仅作客观记录。"
        }
    }

    static func fullChineseDateHeader(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdays = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = (c.weekday ?? 1) >= 1 && (c.weekday ?? 1) <= 7 ? weekdays[c.weekday ?? 1] : ""
        let lunar = HoldingCalendarLogic.lunar(date)
        return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日 · \(weekday) · 农历\(lunar)"
    }
}
