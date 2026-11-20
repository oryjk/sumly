import Foundation
import SwiftUI

// MARK: - 日期解析（统一本地正午，避免时区与夏令时漂移）

enum MacroDateParser {
    /// "yyyy-MM-dd" -> 当地时区当天正午。
    static func parseDay(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return GoldDailyPrice.parseDay(trimmed)
    }

    /// RFC3339 时间戳解析（兼容小数秒）。
    static func parseTimestamp(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return BackendGoldPriceService.parseRFC3339(trimmed)
    }

    static func displayDay(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    static func displaySyncedAt(_ raw: String?) -> String {
        guard let raw else { return "尚未同步" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "尚未同步" }
        if let date = parseTimestamp(trimmed) {
            return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return trimmed
    }
}

// MARK: - 区间与枚举

enum MacroHistoryRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case oneYear = "1y"
    case threeYears = "3y"
    case fiveYears = "5y"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneYear: "1年"
        case .threeYears: "3年"
        case .fiveYears: "5年"
        case .all: "全部"
        }
    }
}

enum MacroExtendedRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case oneYear = "1y"
    case threeYears = "3y"
    case fiveYears = "5y"
    case tenYears = "10y"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneYear: "1年"
        case .threeYears: "3年"
        case .fiveYears: "5年"
        case .tenYears: "10年"
        case .all: "全部"
        }
    }
}

enum MacroDashboardTab: String, CaseIterable, Identifiable, Sendable {
    case temperature = "黄金温度"
    case treasury = "美国国债"
    case panorama = "宏观全景"

    var id: String { rawValue }
}

enum MacroTemperatureLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case freezing
    case cool
    case neutral
    case warm
    case hot

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = MacroTemperatureLevel(rawValue: raw) ?? .neutral
    }

    var defaultLabel: String {
        switch self {
        case .freezing: "极冷低迷"
        case .cool: "偏冷蓄势"
        case .neutral: "温和中性"
        case .warm: "偏热活跃"
        case .hot: "极度火热"
        }
    }

    static func from(score: Double) -> MacroTemperatureLevel {
        guard score.isFinite else { return .neutral }
        switch score {
        case ..<20: return .freezing
        case 20..<40: return .cool
        case 40..<60: return .neutral
        case 60..<80: return .warm
        default: return .hot
        }
    }
}

enum MacroRegimeKind: String, Codable, Sendable, CaseIterable, Hashable {
    case tailwind
    case neutral
    case headwind

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = MacroRegimeKind(rawValue: raw) ?? .neutral
    }

    var defaultLabel: String {
        switch self {
        case .tailwind: "长期宏观顺风"
        case .neutral: "宏观中性"
        case .headwind: "长期宏观逆风"
        }
    }
}

// MARK: - 1. 黄金温度与操作指南针

struct MacroRegime: Codable, Sendable, Equatable {
    let score: Double
    let regime: MacroRegimeKind
    let label: String
    let summary: String

    init(score: Double, regime: MacroRegimeKind, label: String, summary: String) {
        self.score = score
        self.regime = regime
        self.label = label
        self.summary = summary
    }
}

struct MacroActionGuide: Codable, Sendable, Equatable {
    let signal: String
    let title: String
    let summary: String
    let dcaMultiplier: Double
    let dcaLabel: String
    let ma200DeviationPct: Double?
    let ma200Note: String
    let domesticPremiumPct: Double?
    let domesticPremiumNote: String
    let disclaimer: String

    enum CodingKeys: String, CodingKey {
        case signal, title, summary, disclaimer
        case dcaMultiplier = "dca_multiplier"
        case dcaLabel = "dca_label"
        case ma200DeviationPct = "ma200_deviation_pct"
        case ma200Note = "ma200_note"
        case domesticPremiumPct = "domestic_premium_pct"
        case domesticPremiumNote = "domestic_premium_note"
    }

    init(
        signal: String,
        title: String,
        summary: String,
        dcaMultiplier: Double,
        dcaLabel: String,
        ma200DeviationPct: Double?,
        ma200Note: String,
        domesticPremiumPct: Double?,
        domesticPremiumNote: String,
        disclaimer: String
    ) {
        self.signal = signal
        self.title = title
        self.summary = summary
        self.dcaMultiplier = dcaMultiplier
        self.dcaLabel = dcaLabel
        self.ma200DeviationPct = ma200DeviationPct
        self.ma200Note = ma200Note
        self.domesticPremiumPct = domesticPremiumPct
        self.domesticPremiumNote = domesticPremiumNote
        self.disclaimer = disclaimer
    }
}

struct MacroTemperatureDimension: Codable, Sendable, Equatable, Identifiable {
    let key: String
    let name: String
    let weight: Double
    let score: Double
    let available: Bool
    let status: String
    let summary: String
    let metrics: [String: Double]

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, weight, score, available, status, summary, metrics
    }

    init(
        key: String,
        name: String,
        weight: Double,
        score: Double,
        available: Bool,
        status: String,
        summary: String,
        metrics: [String: Double] = [:]
    ) {
        self.key = key
        self.name = name
        self.weight = weight
        self.score = score
        self.available = available
        self.status = status
        self.summary = summary
        self.metrics = metrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        weight = try c.decode(Double.self, forKey: .weight)
        score = try c.decode(Double.self, forKey: .score)
        available = try c.decode(Bool.self, forKey: .available)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        metrics = try c.decodeIfPresent([String: Double].self, forKey: .metrics) ?? [:]
    }
}

struct MacroTemperatureReport: Codable, Sendable, Equatable {
    let asOf: String
    let modelVersion: String
    let degraded: Bool
    let missingFactors: [String]
    let score: Double
    let level: MacroTemperatureLevel
    let levelLabel: String
    let change1d: Double?
    let change5d: Double?
    let volatilityAlert: Bool
    let volatilityNote: String
    let macroRegime: MacroRegime
    let actionGuide: MacroActionGuide
    let dimensions: [MacroTemperatureDimension]

    var asOfDate: Date? { MacroDateParser.parseDay(asOf) }

    /// 后端冷启动无观测数据时返回 `as_of == ""` 且全部维度不可用。
    var hasAvailableData: Bool {
        if asOf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if !dimensions.isEmpty {
            return dimensions.contains(where: \.available)
        }
        return score.isFinite
    }

    var clampedScore: Double {
        MacroPresentation.clampedTemperatureScore(score)
    }

    enum CodingKeys: String, CodingKey {
        case degraded, score, level, dimensions
        case asOf = "as_of"
        case modelVersion = "model_version"
        case missingFactors = "missing_factors"
        case levelLabel = "level_label"
        case change1d = "change_1d"
        case change5d = "change_5d"
        case volatilityAlert = "volatility_alert"
        case volatilityNote = "volatility_note"
        case macroRegime = "macro_regime"
        case actionGuide = "action_guide"
    }

    init(
        asOf: String,
        modelVersion: String,
        degraded: Bool,
        missingFactors: [String],
        score: Double,
        level: MacroTemperatureLevel,
        levelLabel: String,
        change1d: Double?,
        change5d: Double?,
        volatilityAlert: Bool,
        volatilityNote: String,
        macroRegime: MacroRegime,
        actionGuide: MacroActionGuide,
        dimensions: [MacroTemperatureDimension]
    ) {
        self.asOf = asOf
        self.modelVersion = modelVersion
        self.degraded = degraded
        self.missingFactors = missingFactors
        self.score = score
        self.level = level
        self.levelLabel = levelLabel
        self.change1d = change1d
        self.change5d = change5d
        self.volatilityAlert = volatilityAlert
        self.volatilityNote = volatilityNote
        self.macroRegime = macroRegime
        self.actionGuide = actionGuide
        self.dimensions = dimensions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf) ?? ""
        modelVersion = try c.decodeIfPresent(String.self, forKey: .modelVersion) ?? "v1"
        degraded = try c.decodeIfPresent(Bool.self, forKey: .degraded) ?? false
        missingFactors = try c.decodeIfPresent([String].self, forKey: .missingFactors) ?? []
        score = try c.decode(Double.self, forKey: .score)
        level = try c.decode(MacroTemperatureLevel.self, forKey: .level)
        levelLabel = try c.decodeIfPresent(String.self, forKey: .levelLabel) ?? level.defaultLabel
        change1d = try c.decodeIfPresent(Double.self, forKey: .change1d)
        change5d = try c.decodeIfPresent(Double.self, forKey: .change5d)
        volatilityAlert = try c.decodeIfPresent(Bool.self, forKey: .volatilityAlert) ?? false
        volatilityNote = try c.decodeIfPresent(String.self, forKey: .volatilityNote) ?? ""
        macroRegime = try c.decode(MacroRegime.self, forKey: .macroRegime)
        actionGuide = try c.decode(MacroActionGuide.self, forKey: .actionGuide)
        dimensions = try c.decodeIfPresent([MacroTemperatureDimension].self, forKey: .dimensions) ?? []
    }
}

// MARK: - 2. 黄金温度历史曲线

struct MacroTemperatureHistoryPoint: Codable, Sendable, Equatable, Identifiable {
    let dateString: String
    let date: Date
    let score: Double
    let level: MacroTemperatureLevel
    let goldPriceUSD: Double?

    var id: Date { date }

    enum CodingKeys: String, CodingKey {
        case date, score, level
        case goldPriceUSD = "gold_price_usd"
    }

    init(dateString: String, date: Date, score: Double, level: MacroTemperatureLevel, goldPriceUSD: Double?) {
        self.dateString = dateString
        self.date = date
        self.score = score
        self.level = level
        self.goldPriceUSD = goldPriceUSD
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try c.decode(String.self, forKey: .date)
        guard let parsed = MacroDateParser.parseDay(rawDate) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Invalid date: \(rawDate)")
        }
        dateString = rawDate
        date = parsed
        score = try c.decode(Double.self, forKey: .score)
        level = try c.decode(MacroTemperatureLevel.self, forKey: .level)
        goldPriceUSD = try c.decodeIfPresent(Double.self, forKey: .goldPriceUSD)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dateString, forKey: .date)
        try c.encode(score, forKey: .score)
        try c.encode(level, forKey: .level)
        try c.encodeIfPresent(goldPriceUSD, forKey: .goldPriceUSD)
    }
}

struct MacroTemperatureHistory: Codable, Sendable, Equatable {
    let range: String
    let modelVersion: String
    let points: [MacroTemperatureHistoryPoint]

    enum CodingKeys: String, CodingKey {
        case range, points
        case modelVersion = "model_version"
    }

    private struct RawPoint: Decodable {
        let date: String
        let score: Double
        let level: MacroTemperatureLevel
        let goldPriceUSD: Double?

        enum CodingKeys: String, CodingKey {
            case date, score, level
            case goldPriceUSD = "gold_price_usd"
        }
    }

    init(range: String, modelVersion: String, points: [MacroTemperatureHistoryPoint]) {
        self.range = range
        self.modelVersion = modelVersion
        self.points = points.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? MacroHistoryRange.threeYears.rawValue
        modelVersion = try c.decodeIfPresent(String.self, forKey: .modelVersion) ?? "v1"
        let rawPoints = try c.decodeIfPresent([RawPoint].self, forKey: .points) ?? []
        points = rawPoints.compactMap { row in
            guard let day = MacroDateParser.parseDay(row.date), row.score.isFinite else { return nil }
            let price = row.goldPriceUSD.flatMap { $0.isFinite ? $0 : nil }
            return MacroTemperatureHistoryPoint(
                dateString: row.date,
                date: day,
                score: MacroPresentation.clampedTemperatureScore(row.score),
                level: row.level,
                goldPriceUSD: price
            )
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - 通用时序点

struct MacroTimePoint: Codable, Sendable, Equatable, Identifiable {
    let dateString: String
    let date: Date
    let value: Double

    var id: Date { date }

    enum CodingKeys: String, CodingKey {
        case date, value
    }

    init(dateString: String, date: Date, value: Double) {
        self.dateString = dateString
        self.date = date
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try c.decode(String.self, forKey: .date)
        guard let parsed = MacroDateParser.parseDay(rawDate) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Invalid date: \(rawDate)")
        }
        dateString = rawDate
        date = parsed
        value = try c.decode(Double.self, forKey: .value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dateString, forKey: .date)
        try c.encode(value, forKey: .value)
    }
}

private struct RawTimePoint: Decodable {
    let date: String
    let value: Double
}

private func parseTimeSeries(_ raw: [RawTimePoint]?) -> [MacroTimePoint] {
    (raw ?? []).compactMap { row in
        guard let day = MacroDateParser.parseDay(row.date), row.value.isFinite else { return nil }
        return MacroTimePoint(dateString: row.date, date: day, value: row.value)
    }.sorted { $0.date < $1.date }
}

// MARK: - 3. 宏观指标摘要与分组目录

struct MacroIndicatorSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    let seriesID: String
    let nameZh: String
    let section: String
    let unit: String
    let frequency: String
    let source: String
    let goldRelation: String
    let plainNote: String
    let latestDate: String?
    let latestValue: Double?
    let change5d: Double?
    let change20d: Double?
    let change3m: Double?
    let changeYoY: Double?
    let percentile3y: Double?
    let sparkline: [Double]

    var id: String { seriesID }

    enum CodingKeys: String, CodingKey {
        case section, unit, frequency, source, sparkline
        case seriesID = "series_id"
        case nameZh = "name_zh"
        case goldRelation = "gold_relation"
        case plainNote = "plain_note"
        case latestDate = "latest_date"
        case latestValue = "latest_value"
        case change5d = "change_5d"
        case change20d = "change_20d"
        case change3m = "change_3m"
        case changeYoY = "change_yoy"
        case percentile3y = "percentile_3y"
    }

    init(
        seriesID: String,
        nameZh: String,
        section: String,
        unit: String,
        frequency: String,
        source: String,
        goldRelation: String,
        plainNote: String,
        latestDate: String?,
        latestValue: Double?,
        change5d: Double?,
        change20d: Double?,
        change3m: Double?,
        changeYoY: Double?,
        percentile3y: Double?,
        sparkline: [Double]
    ) {
        self.seriesID = seriesID
        self.nameZh = nameZh
        self.section = section
        self.unit = unit
        self.frequency = frequency
        self.source = source
        self.goldRelation = goldRelation
        self.plainNote = plainNote
        self.latestDate = latestDate
        self.latestValue = latestValue
        self.change5d = change5d
        self.change20d = change20d
        self.change3m = change3m
        self.changeYoY = changeYoY
        self.percentile3y = percentile3y
        self.sparkline = sparkline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try c.decode(String.self, forKey: .seriesID)
        nameZh = try c.decode(String.self, forKey: .nameZh)
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        goldRelation = try c.decodeIfPresent(String.self, forKey: .goldRelation) ?? ""
        plainNote = try c.decodeIfPresent(String.self, forKey: .plainNote) ?? ""
        latestDate = try c.decodeIfPresent(String.self, forKey: .latestDate)
        latestValue = try c.decodeIfPresent(Double.self, forKey: .latestValue)
        change5d = try c.decodeIfPresent(Double.self, forKey: .change5d)
        change20d = try c.decodeIfPresent(Double.self, forKey: .change20d)
        change3m = try c.decodeIfPresent(Double.self, forKey: .change3m)
        changeYoY = try c.decodeIfPresent(Double.self, forKey: .changeYoY)
        percentile3y = try c.decodeIfPresent(Double.self, forKey: .percentile3y)
        sparkline = (try c.decodeIfPresent([Double].self, forKey: .sparkline) ?? []).filter(\.isFinite)
    }
}

struct MacroIndicatorSection: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let nameZh: String
    let description: String
    let indicators: [MacroIndicatorSummary]

    enum CodingKeys: String, CodingKey {
        case id, description, indicators
        case nameZh = "name_zh"
    }

    init(id: String, nameZh: String, description: String, indicators: [MacroIndicatorSummary]) {
        self.id = id
        self.nameZh = nameZh
        self.description = description
        self.indicators = indicators
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nameZh = try c.decode(String.self, forKey: .nameZh)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        indicators = try c.decodeIfPresent([MacroIndicatorSummary].self, forKey: .indicators) ?? []
    }
}

struct MacroIndicatorsCatalog: Codable, Sendable, Equatable {
    let sections: [MacroIndicatorSection]

    enum CodingKeys: String, CodingKey {
        case sections
    }

    init(sections: [MacroIndicatorSection]) {
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = try c.decodeIfPresent([MacroIndicatorSection].self, forKey: .sections) ?? []
    }
}

// MARK: - 4. 美国国债专题

struct MacroTreasurySummary: Codable, Sendable, Equatable {
    let totalDebtTrillionUSD: Double?
    let debtChangeYoYTrillion: Double?
    let debtToGDPPct: Double?
    let interestToRevenuePct: Double?
    let fiscalStressScore: Double?
    let yield10yNominalPct: Double?
    let yield2yNominalPct: Double?
    let spread10y2yPct: Double?
    let yield10yRealPct: Double?
    let breakeven10yPct: Double?
    let tltPrice: Double?
    let goldImpactNote: String

    enum CodingKeys: String, CodingKey {
        case totalDebtTrillionUSD = "total_debt_trillion_usd"
        case debtChangeYoYTrillion = "debt_change_yoy_trillion"
        case debtToGDPPct = "debt_to_gdp_pct"
        case interestToRevenuePct = "interest_to_revenue_pct"
        case fiscalStressScore = "fiscal_stress_score"
        case yield10yNominalPct = "yield_10y_nominal_pct"
        case yield2yNominalPct = "yield_2y_nominal_pct"
        case spread10y2yPct = "spread_10y_2y_pct"
        case yield10yRealPct = "yield_10y_real_pct"
        case breakeven10yPct = "breakeven_10y_pct"
        case tltPrice = "tlt_price"
        case goldImpactNote = "gold_impact_note"
    }

    init(
        totalDebtTrillionUSD: Double?,
        debtChangeYoYTrillion: Double?,
        debtToGDPPct: Double?,
        interestToRevenuePct: Double?,
        fiscalStressScore: Double?,
        yield10yNominalPct: Double?,
        yield2yNominalPct: Double?,
        spread10y2yPct: Double?,
        yield10yRealPct: Double?,
        breakeven10yPct: Double?,
        tltPrice: Double?,
        goldImpactNote: String
    ) {
        self.totalDebtTrillionUSD = totalDebtTrillionUSD
        self.debtChangeYoYTrillion = debtChangeYoYTrillion
        self.debtToGDPPct = debtToGDPPct
        self.interestToRevenuePct = interestToRevenuePct
        self.fiscalStressScore = fiscalStressScore
        self.yield10yNominalPct = yield10yNominalPct
        self.yield2yNominalPct = yield2yNominalPct
        self.spread10y2yPct = spread10y2yPct
        self.yield10yRealPct = yield10yRealPct
        self.breakeven10yPct = breakeven10yPct
        self.tltPrice = tltPrice
        self.goldImpactNote = goldImpactNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalDebtTrillionUSD = try c.decodeIfPresent(Double.self, forKey: .totalDebtTrillionUSD)
        debtChangeYoYTrillion = try c.decodeIfPresent(Double.self, forKey: .debtChangeYoYTrillion)
        debtToGDPPct = try c.decodeIfPresent(Double.self, forKey: .debtToGDPPct)
        interestToRevenuePct = try c.decodeIfPresent(Double.self, forKey: .interestToRevenuePct)
        fiscalStressScore = try c.decodeIfPresent(Double.self, forKey: .fiscalStressScore)
        yield10yNominalPct = try c.decodeIfPresent(Double.self, forKey: .yield10yNominalPct)
        yield2yNominalPct = try c.decodeIfPresent(Double.self, forKey: .yield2yNominalPct)
        spread10y2yPct = try c.decodeIfPresent(Double.self, forKey: .spread10y2yPct)
        yield10yRealPct = try c.decodeIfPresent(Double.self, forKey: .yield10yRealPct)
        breakeven10yPct = try c.decodeIfPresent(Double.self, forKey: .breakeven10yPct)
        tltPrice = try c.decodeIfPresent(Double.self, forKey: .tltPrice)
        goldImpactNote = try c.decodeIfPresent(String.self, forKey: .goldImpactNote) ?? ""
    }
}

struct MacroTreasuryReport: Codable, Sendable, Equatable {
    let asOf: String
    let summary: MacroTreasurySummary
    let cards: [MacroIndicatorSummary]
    let debtSeries: [MacroTimePoint]
    let realYieldSeries: [MacroTimePoint]
    let nominalYieldSeries: [MacroTimePoint]

    var hasAnyData: Bool {
        summary.totalDebtTrillionUSD != nil
            || summary.yield10yRealPct != nil
            || summary.yield10yNominalPct != nil
            || !debtSeries.isEmpty
            || !realYieldSeries.isEmpty
            || !nominalYieldSeries.isEmpty
            || !cards.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case summary, cards
        case asOf = "as_of"
        case debtSeries = "debt_series"
        case realYieldSeries = "real_yield_series"
        case nominalYieldSeries = "nominal_yield_series"
    }

    init(
        asOf: String,
        summary: MacroTreasurySummary,
        cards: [MacroIndicatorSummary],
        debtSeries: [MacroTimePoint],
        realYieldSeries: [MacroTimePoint],
        nominalYieldSeries: [MacroTimePoint]
    ) {
        self.asOf = asOf
        self.summary = summary
        self.cards = cards
        self.debtSeries = debtSeries.sorted { $0.date < $1.date }
        self.realYieldSeries = realYieldSeries.sorted { $0.date < $1.date }
        self.nominalYieldSeries = nominalYieldSeries.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf) ?? ""
        summary = try c.decode(MacroTreasurySummary.self, forKey: .summary)
        cards = try c.decodeIfPresent([MacroIndicatorSummary].self, forKey: .cards) ?? []
        debtSeries = parseTimeSeries(try c.decodeIfPresent([RawTimePoint].self, forKey: .debtSeries))
        realYieldSeries = parseTimeSeries(try c.decodeIfPresent([RawTimePoint].self, forKey: .realYieldSeries))
        nominalYieldSeries = parseTimeSeries(try c.decodeIfPresent([RawTimePoint].self, forKey: .nominalYieldSeries))
    }
}

// MARK: - 5. 单个指标详情

struct MacroPercentileWindow: Codable, Sendable, Equatable, Identifiable {
    let window: String
    let percentile: Double?
    let observationCount: Int

    var id: String { window }

    var windowTitle: String {
        switch window.lowercased() {
        case "1y": "近1年"
        case "3y": "近3年"
        case "5y": "近5年"
        case "10y": "近10年"
        case "all": "全部历史"
        default: window
        }
    }

    enum CodingKeys: String, CodingKey {
        case window, percentile
        case observationCount = "observation_count"
    }

    init(window: String, percentile: Double?, observationCount: Int) {
        self.window = window
        self.percentile = percentile
        self.observationCount = observationCount
    }
}

struct MacroIndicatorDetail: Codable, Sendable, Equatable {
    let seriesID: String
    let nameZh: String
    let section: String
    let unit: String
    let frequency: String
    let source: String
    let goldRelation: String
    let plainNote: String
    let latestDate: String?
    let latestValue: Double?
    let change5d: Double?
    let change20d: Double?
    let change3m: Double?
    let changeYoY: Double?
    let percentile3y: Double?
    let range: String
    let percentiles: [MacroPercentileWindow]
    let lastSyncedAt: String?
    let syncStatus: String
    let observations: [MacroTimePoint]

    enum CodingKeys: String, CodingKey {
        case section, unit, frequency, source, range, percentiles, observations
        case seriesID = "series_id"
        case nameZh = "name_zh"
        case goldRelation = "gold_relation"
        case plainNote = "plain_note"
        case latestDate = "latest_date"
        case latestValue = "latest_value"
        case change5d = "change_5d"
        case change20d = "change_20d"
        case change3m = "change_3m"
        case changeYoY = "change_yoy"
        case percentile3y = "percentile_3y"
        case lastSyncedAt = "last_synced_at"
        case syncStatus = "sync_status"
    }

    init(
        seriesID: String,
        nameZh: String,
        section: String,
        unit: String,
        frequency: String,
        source: String,
        goldRelation: String,
        plainNote: String,
        latestDate: String?,
        latestValue: Double?,
        change5d: Double?,
        change20d: Double?,
        change3m: Double?,
        changeYoY: Double?,
        percentile3y: Double?,
        range: String,
        percentiles: [MacroPercentileWindow],
        lastSyncedAt: String?,
        syncStatus: String,
        observations: [MacroTimePoint]
    ) {
        self.seriesID = seriesID
        self.nameZh = nameZh
        self.section = section
        self.unit = unit
        self.frequency = frequency
        self.source = source
        self.goldRelation = goldRelation
        self.plainNote = plainNote
        self.latestDate = latestDate
        self.latestValue = latestValue
        self.change5d = change5d
        self.change20d = change20d
        self.change3m = change3m
        self.changeYoY = changeYoY
        self.percentile3y = percentile3y
        self.range = range
        self.percentiles = percentiles
        self.lastSyncedAt = lastSyncedAt
        self.syncStatus = syncStatus
        self.observations = observations.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try c.decode(String.self, forKey: .seriesID)
        nameZh = try c.decode(String.self, forKey: .nameZh)
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        goldRelation = try c.decodeIfPresent(String.self, forKey: .goldRelation) ?? ""
        plainNote = try c.decodeIfPresent(String.self, forKey: .plainNote) ?? ""
        latestDate = try c.decodeIfPresent(String.self, forKey: .latestDate)
        latestValue = try c.decodeIfPresent(Double.self, forKey: .latestValue)
        change5d = try c.decodeIfPresent(Double.self, forKey: .change5d)
        change20d = try c.decodeIfPresent(Double.self, forKey: .change20d)
        change3m = try c.decodeIfPresent(Double.self, forKey: .change3m)
        changeYoY = try c.decodeIfPresent(Double.self, forKey: .changeYoY)
        percentile3y = try c.decodeIfPresent(Double.self, forKey: .percentile3y)
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? MacroExtendedRange.fiveYears.rawValue
        percentiles = try c.decodeIfPresent([MacroPercentileWindow].self, forKey: .percentiles) ?? []
        lastSyncedAt = try c.decodeIfPresent(String.self, forKey: .lastSyncedAt)
        syncStatus = try c.decodeIfPresent(String.self, forKey: .syncStatus) ?? "pending"
        observations = parseTimeSeries(try c.decodeIfPresent([RawTimePoint].self, forKey: .observations))
    }
}

// MARK: - 6. CFTC 黄金持仓（COT）

struct MacroCotPoint: Codable, Sendable, Equatable, Identifiable {
    let dateString: String
    let date: Date
    let mmLong: Double
    let mmShort: Double
    let mmNet: Double
    let swapLong: Double
    let swapShort: Double
    let swapNet: Double
    let openInterest: Double
    let mmNetRatioPct: Double?

    var id: Date { date }

    enum CodingKeys: String, CodingKey {
        case date
        case mmLong = "mm_long"
        case mmShort = "mm_short"
        case mmNet = "mm_net"
        case swapLong = "swap_long"
        case swapShort = "swap_short"
        case swapNet = "swap_net"
        case openInterest = "open_interest"
        case mmNetRatioPct = "mm_net_ratio_pct"
    }

    init(
        dateString: String,
        date: Date,
        mmLong: Double,
        mmShort: Double,
        mmNet: Double,
        swapLong: Double,
        swapShort: Double,
        swapNet: Double,
        openInterest: Double,
        mmNetRatioPct: Double?
    ) {
        self.dateString = dateString
        self.date = date
        self.mmLong = mmLong
        self.mmShort = mmShort
        self.mmNet = mmNet
        self.swapLong = swapLong
        self.swapShort = swapShort
        self.swapNet = swapNet
        self.openInterest = openInterest
        self.mmNetRatioPct = mmNetRatioPct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try c.decode(String.self, forKey: .date)
        guard let parsed = MacroDateParser.parseDay(rawDate) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Invalid COT date: \(rawDate)")
        }
        dateString = rawDate
        date = parsed
        mmLong = try c.decode(Double.self, forKey: .mmLong)
        mmShort = try c.decode(Double.self, forKey: .mmShort)
        mmNet = try c.decode(Double.self, forKey: .mmNet)
        swapLong = try c.decode(Double.self, forKey: .swapLong)
        swapShort = try c.decode(Double.self, forKey: .swapShort)
        swapNet = try c.decode(Double.self, forKey: .swapNet)
        openInterest = try c.decode(Double.self, forKey: .openInterest)
        mmNetRatioPct = try c.decodeIfPresent(Double.self, forKey: .mmNetRatioPct)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dateString, forKey: .date)
        try c.encode(mmLong, forKey: .mmLong)
        try c.encode(mmShort, forKey: .mmShort)
        try c.encode(mmNet, forKey: .mmNet)
        try c.encode(swapLong, forKey: .swapLong)
        try c.encode(swapShort, forKey: .swapShort)
        try c.encode(swapNet, forKey: .swapNet)
        try c.encode(openInterest, forKey: .openInterest)
        try c.encodeIfPresent(mmNetRatioPct, forKey: .mmNetRatioPct)
    }
}

struct MacroCotReport: Codable, Sendable, Equatable {
    let seriesID: String
    let range: String
    let latest: MacroCotPoint?
    let points: [MacroCotPoint]

    enum CodingKeys: String, CodingKey {
        case range, latest, points
        case seriesID = "series_id"
    }

    private struct RawCotPoint: Decodable {
        let date: String
        let mmLong: Double
        let mmShort: Double
        let mmNet: Double
        let swapLong: Double
        let swapShort: Double
        let swapNet: Double
        let openInterest: Double
        let mmNetRatioPct: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case mmLong = "mm_long"
            case mmShort = "mm_short"
            case mmNet = "mm_net"
            case swapLong = "swap_long"
            case swapShort = "swap_short"
            case swapNet = "swap_net"
            case openInterest = "open_interest"
            case mmNetRatioPct = "mm_net_ratio_pct"
        }

        func toModel() -> MacroCotPoint? {
            guard let day = MacroDateParser.parseDay(date),
                  mmLong.isFinite, mmShort.isFinite, mmNet.isFinite,
                  swapLong.isFinite, swapShort.isFinite, swapNet.isFinite,
                  openInterest.isFinite else { return nil }
            let ratio = mmNetRatioPct.flatMap { $0.isFinite ? $0 : nil }
            return MacroCotPoint(
                dateString: date,
                date: day,
                mmLong: mmLong,
                mmShort: mmShort,
                mmNet: mmNet,
                swapLong: swapLong,
                swapShort: swapShort,
                swapNet: swapNet,
                openInterest: openInterest,
                mmNetRatioPct: ratio
            )
        }
    }

    init(seriesID: String, range: String, latest: MacroCotPoint?, points: [MacroCotPoint]) {
        self.seriesID = seriesID
        self.range = range
        self.latest = latest
        self.points = points.sorted { $0.date < $1.date }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = try c.decodeIfPresent(String.self, forKey: .seriesID) ?? "GOLD_COT"
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? MacroHistoryRange.threeYears.rawValue
        latest = try c.decodeIfPresent(RawCotPoint.self, forKey: .latest)?.toModel()
        let rawPoints = try c.decodeIfPresent([RawCotPoint].self, forKey: .points) ?? []
        points = rawPoints.compactMap { $0.toModel() }.sorted { $0.date < $1.date }
    }
}

// MARK: - 展示、格式化与颜色映射纯逻辑

enum MacroPresentation {
    static func clampedTemperatureScore(_ score: Double) -> Double {
        guard score.isFinite else { return 0 }
        return min(max(score, 0), 100)
    }

    static func temperatureColor(for level: MacroTemperatureLevel) -> Color {
        switch level {
        case .freezing: GoldTheme.tempFreezing
        case .cool: GoldTheme.tempCool
        case .neutral: GoldTheme.tempNeutral
        case .warm: GoldTheme.tempWarm
        case .hot: GoldTheme.tempHot
        }
    }

    static func temperatureColor(forScore score: Double) -> Color {
        temperatureColor(for: MacroTemperatureLevel.from(score: score))
    }

    static func regimeColor(for regime: MacroRegimeKind) -> Color {
        switch regime {
        case .tailwind: GoldTheme.up
        case .neutral: GoldTheme.goldSoft
        case .headwind: GoldTheme.down
        }
    }

    /// 遵循国内红涨绿跌配色习惯。
    static func changeColor(for delta: Double?) -> Color {
        guard let delta, delta.isFinite, delta != 0 else { return GoldTheme.textSecondary }
        return delta > 0 ? GoldTheme.up : GoldTheme.down
    }

    static func syncStatusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "ok", "success", "synced": GoldTheme.down
        case "error", "failed": GoldTheme.up
        case "skipped", "pending": GoldTheme.goldSoft
        default: GoldTheme.textSecondary
        }
    }

    static func syncStatusLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "ok", "success", "synced": "数据正常"
        case "error", "failed": "同步异常"
        case "skipped": "已跳过（未配置数据源）"
        case "pending", "": "待同步"
        default: raw
        }
    }

    static func goldRelationLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "positive", "bullish", "same": "与金价同向"
        case "negative", "inverse", "bearish": "与金价反向"
        case "neutral", "mixed", "reference": "综合参考"
        case "": "宏观关联"
        default: raw
        }
    }

    static func frequencyLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "daily": "日频"
        case "weekly": "周频"
        case "monthly": "月频"
        case "quarterly": "季频"
        case "annual", "yearly": "年频"
        case "": "—"
        default: raw
        }
    }

    static func factorDisplayName(_ key: String) -> String {
        switch key.lowercased() {
        case "trend_momentum": "趋势与动量"
        case "positioning": "期货持仓拥挤度"
        case "domestic_premium": "国内金价溢价"
        case "flow_cross_asset": "资金流与跨资产"
        case "macro_pulse": "宏观脉冲"
        default: key
        }
    }

    static func formatScore(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f°", clampedTemperatureScore(value))
    }

    static func formatSignedPoints(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", value))°"
    }

    static func formatDCAMultiplier(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.1fx", max(0, value))
    }

    static func formatPercent(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", value))%"
    }

    private static func signPrefix(for value: Double, signed: Bool) -> String {
        if value < 0 { return "-" }
        if signed && value > 0 { return "+" }
        return ""
    }

    static func formatTrillionUSD(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let sign = signPrefix(for: value, signed: signed)
        return "\(sign)$\(String(format: "%.2f", abs(value))) 万亿"
    }

    static func formatContracts(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let absVal = abs(value)
        let prefix = signPrefix(for: value, signed: signed)
        if absVal >= 10_000 {
            return "\(prefix)\(String(format: "%.2f", absVal / 10_000)) 万手"
        }
        return "\(prefix)\(Int(absVal.rounded())) 手"
    }

    static func formatValue(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "—" }
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sign = signPrefix(for: value, signed: false)
        let absVal = abs(value)
        switch normalized {
        case "%", "pct", "percent", "percentage":
            return String(format: "%.2f%%", value)
        case "trillion_usd", "usd_trillion":
            return "\(sign)$\(String(format: "%.2f", absVal)) 万亿"
        case "billion_usd", "usd_billion":
            if absVal >= 1_000 {
                return "\(sign)$\(String(format: "%.2f", absVal / 1_000)) 万亿"
            }
            return "\(sign)$\(String(format: "%.1f", absVal))B"
        case "million_usd", "usd_million":
            if absVal >= 1_000_000 {
                return "\(sign)$\(String(format: "%.2f", absVal / 1_000_000)) 万亿"
            }
            if absVal >= 1_000 {
                return "\(sign)$\(String(format: "%.1f", absVal / 1_000))B"
            }
            return "\(sign)$\(String(format: "%.1f", absVal))M"
        case "tons", "tonnes":
            return String(format: "%.1f 吨", value)
        case "usd", "usd/oz", "usd_oz", "usd/troy_oz", "usd/bbl":
            return "\(sign)$" + absVal.formatted(.number.precision(.fractionLength(2)))
        case "cny/g", "cny_g":
            return "\(sign)¥" + absVal.formatted(.number.precision(.fractionLength(2)))
        case "contracts":
            return formatContracts(value)
        case "index", "score", "ratio", "points", "":
            return String(format: "%.2f", value)
        default:
            return "\(String(format: "%.2f", value)) \(unit)"
        }
    }

    static func formatDelta(_ value: Double?, unit: String) -> String {
        guard let value, value.isFinite else { return "—" }
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sign = signPrefix(for: value, signed: true)
        let absVal = abs(value)
        switch normalized {
        case "%", "pct", "percent", "percentage":
            return "\(sign)\(String(format: "%.2f", absVal))%"
        case "trillion_usd", "usd_trillion":
            return "\(sign)\(String(format: "%.2f", absVal)) 万亿"
        case "billion_usd", "usd_billion":
            if absVal >= 1_000 {
                return "\(sign)\(String(format: "%.2f", absVal / 1_000)) 万亿"
            }
            return "\(sign)\(String(format: "%.1f", absVal))B"
        case "million_usd", "usd_million":
            if absVal >= 1_000_000 {
                return "\(sign)\(String(format: "%.2f", absVal / 1_000_000)) 万亿"
            }
            if absVal >= 1_000 {
                return "\(sign)\(String(format: "%.1f", absVal / 1_000))B"
            }
            return "\(sign)\(String(format: "%.1f", absVal))M"
        case "tons", "tonnes":
            return "\(sign)\(String(format: "%.1f", absVal)) 吨"
        case "contracts":
            return formatContracts(value, signed: true)
        default:
            return "\(sign)\(String(format: "%.2f", absVal))"
        }
    }

    static func formatPercentile(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", min(max(value, 0), 100))
    }

    static func percentileBadgeText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "分位待积累" }
        let clamped = min(max(value, 0), 100)
        let tier: String
        switch clamped {
        case ..<20: tier = "极低位"
        case 20..<40: tier = "偏低位"
        case 40..<60: tier = "中位区"
        case 60..<80: tier = "偏高位"
        default: tier = "极高位"
        }
        return "\(String(format: "%.0f", clamped))% · \(tier)"
    }

    /// 将原始序列归一化到 0...1，用于迷你 sparkline 渲染。
    static func normalizedSparkline(_ values: [Double]) -> [Double] {
        let valid = values.filter(\.isFinite)
        guard !valid.isEmpty else { return [] }
        guard let low = valid.min(), let high = valid.max() else { return [] }
        let span = high - low
        guard span > 1e-12 else {
            return Array(repeating: 0.5, count: valid.count)
        }
        return valid.map { ($0 - low) / span }
    }
}
