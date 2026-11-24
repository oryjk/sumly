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
        guard let raw else { return L10n.tr("尚未同步") }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.tr("尚未同步") }
        if let date = parseTimestamp(trimmed) {
            return date.formatted(
                Date.FormatStyle(locale: AppLanguage.currentLocale)
                    .year()
                    .month(.twoDigits)
                    .day(.twoDigits)
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits)
            )
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
        case .oneYear: L10n.tr("1年")
        case .threeYears: L10n.tr("3年")
        case .fiveYears: L10n.tr("5年")
        case .all: L10n.tr("全部")
        }
    }

    var localizedTitle: String { title }
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
        case .oneYear: L10n.tr("1年")
        case .threeYears: L10n.tr("3年")
        case .fiveYears: L10n.tr("5年")
        case .tenYears: L10n.tr("10年")
        case .all: L10n.tr("全部")
        }
    }

    var localizedTitle: String { title }
}

enum MacroDashboardTab: String, CaseIterable, Identifiable, Sendable {
    case temperature = "黄金温度"
    case treasury = "美国国债"
    case panorama = "宏观全景"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .temperature: L10n.tr("黄金温度")
        case .treasury: L10n.tr("美国国债")
        case .panorama: L10n.tr("宏观全景")
        }
    }
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
        case .freezing: L10n.tr("极冷区间")
        case .cool: L10n.tr("偏冷区间")
        case .neutral: L10n.tr("中性区间")
        case .warm: L10n.tr("偏热区间")
        case .hot: L10n.tr("极热区间")
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
        case .tailwind: L10n.tr("支撑偏强")
        case .neutral: L10n.tr("背景中性")
        case .headwind: L10n.tr("支撑偏弱")
        }
    }
}

/// 短期交易热度（0~100°）与长期宏观背景（0~100分）分栏解读纯数据模型。
/// 100% 由客户端枚举与分值映射生成，不透传服务端历史遗留的“偏暖”或投顾表述。
struct MacroDualHorizonSummary: Sendable, Equatable {
    let shortTermLevel: MacroTemperatureLevel
    let shortTermScore: Double
    let shortTermLevelLabel: String
    let shortTermCompactTitle: String
    let shortTermState: String
    let shortTermCrowding: String
    let shortTermPlainNote: String
    let shortTermDetailNote: String

    let longTermRegime: MacroRegimeKind
    let longTermScore: Double
    let longTermScoreText: String
    let longTermState: String
    let longTermPlainNote: String
    let longTermDetailNote: String

    let combinedPatternLabel: String
    let combinedSummary: String
}

// MARK: - 1. 黄金温度与市场状态解读

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

    var localizedName: String {
        MacroLocalization.dimensionName(self)
    }

    var localizedSummary: String {
        MacroLocalization.dimensionSummary(self)
    }

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

struct MacroTemperatureGuideLevel: Codable, Sendable, Equatable, Identifiable {
    let range: String
    let level: MacroTemperatureLevel
    let label: String
    let description: String

    var id: String { "\(level.rawValue)-\(range)" }

    enum CodingKeys: String, CodingKey {
        case range, level, label, description
    }

    init(
        range: String,
        level: MacroTemperatureLevel,
        label: String,
        description: String
    ) {
        self.range = range
        self.level = level
        self.label = label
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = try c.decodeIfPresent(String.self, forKey: .range) ?? ""
        level = try c.decodeIfPresent(MacroTemperatureLevel.self, forKey: .level) ?? .neutral
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? level.defaultLabel
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

struct MacroTemperatureGuideHelp: Codable, Sendable, Equatable {
    let title: String
    let methodology: String
    let levels: [MacroTemperatureGuideLevel]
    let officialAccountName: String
    let officialAccountNote: String

    static var defaultOfficialAccountNote: String {
        L10n.tr("每日宏观数据复盘与模型方法论笔记同步更新于微信公众号")
    }

    static var defaultGuide: MacroTemperatureGuideHelp {
        MacroTemperatureGuideHelp(
            title: L10n.tr("黄金温度计说明"),
            methodology: L10n.tr("黄金温度计综合趋势偏离、机构持仓拥挤度、国内溢价、资金流与跨品种强弱、实际利率与美元短期共振共 5 个维度，基于近 3 年滚动历史分位加权合成（0°~100°），仅客观刻画市场冷热与拥挤程度，不构成投资建议。"),
            levels: [
                MacroTemperatureGuideLevel(
                    range: "0° ~ 20°",
                    level: .freezing,
                    label: L10n.tr("极冷区间"),
                    description: L10n.tr("情绪与交易热度处于近 3 年低位，市场关注度低迷")
                ),
                MacroTemperatureGuideLevel(
                    range: "20° ~ 40°",
                    level: .cool,
                    label: L10n.tr("偏冷区间"),
                    description: L10n.tr("交易拥挤度较低，市场情绪尚未过热")
                ),
                MacroTemperatureGuideLevel(
                    range: "40° ~ 60°",
                    level: .neutral,
                    label: L10n.tr("中性区间"),
                    description: L10n.tr("多空力量相对均衡，市场热度处于常态")
                ),
                MacroTemperatureGuideLevel(
                    range: "60° ~ 80°",
                    level: .warm,
                    label: L10n.tr("偏热区间"),
                    description: L10n.tr("资金关注度升温，交投活跃度偏高")
                ),
                MacroTemperatureGuideLevel(
                    range: "80° ~ 100°",
                    level: .hot,
                    label: L10n.tr("极热区间"),
                    description: L10n.tr("短期偏离与多头拥挤度处于高位，历史波动往往放大")
                )
            ],
            officialAccountName: "",
            officialAccountNote: ""
        )
    }

    var displayTitle: String {
        guard MacroLocalization.isChinese else { return Self.defaultGuide.title }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultGuide.title : trimmed
    }

    var displayMethodology: String {
        guard MacroLocalization.isChinese else { return Self.defaultGuide.methodology }
        let trimmed = methodology.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultGuide.methodology : trimmed
    }

    var displayLevels: [MacroTemperatureGuideLevel] {
        guard !levels.isEmpty else { return Self.defaultGuide.levels }
        if MacroLocalization.isChinese {
            return levels
        }
        return levels.map { item in
            MacroTemperatureGuideLevel(
                range: item.range,
                level: item.level,
                label: MacroLocalization.guideLevelLabel(for: item),
                description: MacroLocalization.guideLevelDescription(for: item)
            )
        }
    }

    var trimmedOfficialAccountName: String {
        officialAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedOfficialAccountNote: String {
        if MacroLocalization.isChinese {
            let trimmed = officialAccountNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return hasOfficialAccount ? Self.defaultOfficialAccountNote : ""
    }

    var hasOfficialAccount: Bool {
        !trimmedOfficialAccountName.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case title, methodology, levels
        case officialAccountName = "official_account_name"
        case officialAccountNote = "official_account_note"
    }

    init(
        title: String,
        methodology: String,
        levels: [MacroTemperatureGuideLevel],
        officialAccountName: String = "",
        officialAccountNote: String = ""
    ) {
        self.title = title
        self.methodology = methodology
        self.levels = levels
        self.officialAccountName = officialAccountName
        self.officialAccountNote = officialAccountNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        methodology = try c.decodeIfPresent(String.self, forKey: .methodology) ?? ""
        levels = try c.decodeIfPresent([MacroTemperatureGuideLevel].self, forKey: .levels) ?? []
        officialAccountName = try c.decodeIfPresent(String.self, forKey: .officialAccountName) ?? ""
        officialAccountNote = try c.decodeIfPresent(String.self, forKey: .officialAccountNote) ?? ""
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
    let guideHelp: MacroTemperatureGuideHelp?

    var asOfDate: Date? { MacroDateParser.parseDay(asOf) }

    var resolvedGuideHelp: MacroTemperatureGuideHelp {
        guideHelp ?? .defaultGuide
    }

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
        case guideHelp = "guide_help"
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
        dimensions: [MacroTemperatureDimension],
        guideHelp: MacroTemperatureGuideHelp? = nil
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
        self.guideHelp = guideHelp
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
        guideHelp = try c.decodeIfPresent(MacroTemperatureGuideHelp.self, forKey: .guideHelp)
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

    var localizedName: String {
        MacroLocalization.indicatorName(seriesID: seriesID, fallback: nameZh)
    }

    var localizedPlainNote: String {
        MacroLocalization.indicatorPlainNote(seriesID: seriesID, fallback: plainNote)
    }

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

    var localizedName: String {
        MacroLocalization.sectionName(id: id, fallback: nameZh)
    }

    var localizedDescription: String {
        MacroLocalization.sectionDescription(id: id, fallback: description)
    }

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

    var localizedGoldImpactNote: String {
        MacroLocalization.treasuryGoldImpactNote(for: self)
    }

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
        case "1y": L10n.tr("近1年")
        case "3y": L10n.tr("近3年")
        case "5y": L10n.tr("近5年")
        case "10y": L10n.tr("近10年")
        case "all": L10n.tr("全部历史")
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

    var localizedName: String {
        MacroLocalization.indicatorName(seriesID: seriesID, fallback: nameZh)
    }

    var localizedPlainNote: String {
        MacroLocalization.indicatorPlainNote(seriesID: seriesID, fallback: plainNote)
    }

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
        case .tailwind: GoldTheme.gold
        case .neutral: GoldTheme.textSecondary
        case .headwind: GoldTheme.tempFreezing
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
        case "ok", "success", "synced": L10n.tr("数据正常")
        case "error", "failed": L10n.tr("同步异常")
        case "skipped": L10n.tr("已跳过（未配置数据源）")
        case "pending", "": L10n.tr("待同步")
        default: raw
        }
    }

    static func goldRelationLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "positive", "bullish", "same": L10n.tr("与金价同向")
        case "negative", "inverse", "bearish": L10n.tr("与金价反向")
        case "neutral", "mixed", "reference": L10n.tr("综合参考")
        case "": L10n.tr("宏观关联")
        default: raw
        }
    }

    static func frequencyLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "daily": L10n.tr("日频")
        case "weekly": L10n.tr("周频")
        case "monthly": L10n.tr("月频")
        case "quarterly": L10n.tr("季频")
        case "annual", "yearly": L10n.tr("年频")
        case "": "—"
        default: raw
        }
    }

    static func sourceLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        switch trimmed.lowercased() {
        case "treasury": return L10n.tr("美国财政部")
        case "fred": return L10n.tr("美联储经济数据（FRED）")
        case "yahoo": return L10n.tr("雅虎财经")
        case "spdr": return L10n.tr("SPDR 黄金 ETF 官方")
        case "cftc": return L10n.tr("美国商品期货交易委员会（CFTC）")
        case "bitcoin": return "Blockchain.com"
        case "imf": return L10n.tr("国际货币基金组织（IMF）")
        case "seedcsv": return L10n.tr("历史统计归档")
        case "derived": return L10n.tr("公开数据衍生计算")
        default: return trimmed
        }
    }

    static func unitLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        switch trimmed.lowercased() {
        case "trillion_usd": return L10n.tr("万亿美元")
        case "billion_usd": return L10n.tr("十亿美元")
        case "million_usd": return L10n.tr("百万美元")
        case "usd": return L10n.tr("美元")
        case "percent", "%": return L10n.tr("百分比（%）")
        case "index": return L10n.tr("指数点")
        case "tons": return L10n.tr("吨")
        case "contracts": return L10n.tr("手（期货合约）")
        case "ratio": return L10n.tr("比值")
        case "cny/usd": return L10n.tr("人民币/美元")
        case "cny/g": return L10n.tr("人民币/克")
        default: return trimmed
        }
    }

    static func factorDisplayName(_ key: String) -> String {
        switch key.lowercased() {
        case "trend_momentum": L10n.tr("趋势与动量")
        case "positioning": L10n.tr("期货持仓拥挤度")
        case "domestic_premium": L10n.tr("国内金价溢价")
        case "flow_cross_asset": L10n.tr("资金流与跨资产")
        case "macro_pulse": L10n.tr("宏观脉冲")
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

    static var defaultDisclaimer: String {
        L10n.tr("数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。")
    }

    static let advisoryKeywords: [String] = [
        "操作指南针", "逢低", "加配", "定投", "加仓", "减仓", "止盈", "建仓", "追高",
        "抄底", "知识星球", "付费社群", "建议", "适合", "划算", "黄金坑", "安全垫",
        "分批", "仓位", "买入", "卖出", "放慢节奏", "防守", "试探",
        "便宜", "贵", "买点", "卖点", "机会", "配置", "入场", "离场"
    ]

    static func containsAdvisoryTerms(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return advisoryKeywords.contains { trimmed.contains($0) }
    }

    static func dualHorizonSummary(for report: MacroTemperatureReport) -> MacroDualHorizonSummary {
        dualHorizonSummary(
            level: report.level,
            shortScore: report.score,
            regime: report.macroRegime.regime,
            longScore: report.macroRegime.score
        )
    }

    static func dualHorizonSummary(
        level: MacroTemperatureLevel,
        shortScore: Double,
        regime: MacroRegimeKind,
        longScore: Double
    ) -> MacroDualHorizonSummary {
        let clampedShort = clampedTemperatureScore(shortScore)
        let clampedLong = clampedTemperatureScore(longScore)
        let longScoreText = L10n.fmt("%lld分", Int64(clampedLong.rounded()))

        let shortCompactTitle: String
        let shortState: String
        let shortCrowding: String
        let shortPlainNote: String
        let shortDetailNote: String

        switch level {
        case .freezing:
            shortCompactTitle = L10n.tr("极冷 · 交投清淡")
            shortState = L10n.tr("交投极冷")
            shortCrowding = L10n.tr("拥挤度极低")
            shortPlainNote = L10n.tr("近期交投极冷，市场关注度低迷")
            shortDetailNote = L10n.tr("短期五维热度处于近 3 年极低分位，市场交投清淡、拥挤度极低。")
        case .cool:
            shortCompactTitle = L10n.tr("偏冷 · 拥挤度低")
            shortState = L10n.tr("交投偏冷")
            shortCrowding = L10n.tr("拥挤度较低")
            shortPlainNote = L10n.tr("近期交投偏冷，市场情绪未过热")
            shortDetailNote = L10n.tr("短期五维热度处于近 3 年偏低分位，交易拥挤度较低、情绪尚未过热。")
        case .neutral:
            shortCompactTitle = L10n.tr("中性 · 多空均衡")
            shortState = L10n.tr("热度适中")
            shortCrowding = L10n.tr("热度均衡")
            shortPlainNote = L10n.tr("近期交投平稳，多空力量较均衡")
            shortDetailNote = L10n.tr("短期五维热度处于近 3 年中位区间，多空力量与交投活跃度相对均衡。")
        case .warm:
            shortCompactTitle = L10n.tr("偏热 · 关注升温")
            shortState = L10n.tr("交投偏热")
            shortCrowding = L10n.tr("关注度偏高")
            shortPlainNote = L10n.tr("近期交投升温，资金关注度偏高")
            shortDetailNote = L10n.tr("短期五维热度处于近 3 年偏高分位，资金关注度升温、交投活跃度偏高。")
        case .hot:
            shortCompactTitle = L10n.tr("过热 · 拥挤度高")
            shortState = L10n.tr("交易过热")
            shortCrowding = L10n.tr("拥挤度偏高")
            shortPlainNote = L10n.tr("近期交投过热，多头拥挤度偏高")
            shortDetailNote = L10n.tr("短期五维热度处于近 3 年高位区间，短期偏离与多头拥挤度均处于高位。")
        }

        let longState: String
        let longPlainNote: String
        let longDetailNote: String

        switch regime {
        case .tailwind:
            longState = L10n.tr("支撑偏强")
            longPlainNote = L10n.tr("美债与央行购金等长期支撑较强")
            longDetailNote = L10n.tr("美债规模、财政压力与央行购金等长期宏观指标整体偏强，中长期基本面支撑较强。")
        case .neutral:
            longState = L10n.tr("背景中性")
            longPlainNote = L10n.tr("实际利率与美债等长期因素均衡")
            longDetailNote = L10n.tr("实际利率水平与美债规模、央行购金等长期宏观指标力量相对均衡，整体处于中性背景。")
        case .headwind:
            longState = L10n.tr("支撑偏弱")
            longPlainNote = L10n.tr("实际利率偏高等使长期背景偏弱")
            longDetailNote = L10n.tr("实际利率水平相对偏高且财政与外储端驱动偏弱，中长期宏观支撑相对偏弱。")
        }

        let combinedPatternLabel: String
        let combinedSummary: String

        switch (level, regime) {
        case (.freezing, .tailwind):
            combinedPatternLabel = L10n.tr("极冷长强")
            combinedSummary = L10n.tr("短期交投极冷、拥挤度处于近 3 年极低分位，而长期美债与央行购金等宏观支撑偏强，短长周期呈现明显错位。")
        case (.freezing, .neutral):
            combinedPatternLabel = L10n.tr("极冷长平")
            combinedSummary = L10n.tr("短期交投极冷、市场关注度低迷，同时长期实际利率与美债等宏观背景处于中性常态。")
        case (.freezing, .headwind):
            combinedPatternLabel = L10n.tr("极冷长弱")
            combinedSummary = L10n.tr("短期交投极冷、市场活跃度处于近 3 年低位，同时长期宏观指标支撑偏弱，短期低迷与长期偏弱并存。")
        case (.cool, .tailwind):
            combinedPatternLabel = L10n.tr("短冷长强")
            combinedSummary = L10n.tr("短期交投偏冷、交易拥挤度较低，而长期美债与央行购金等宏观支撑依然偏强，短长周期呈现温和错位。")
        case (.cool, .neutral):
            combinedPatternLabel = L10n.tr("短冷长平")
            combinedSummary = L10n.tr("短期交投偏冷、交易拥挤度较低，同时长期宏观基本面各项指标力量相对均衡。")
        case (.cool, .headwind):
            combinedPatternLabel = L10n.tr("短冷长弱")
            combinedSummary = L10n.tr("短期交投偏冷、交易活跃度偏低，同时长期实际利率与财政端等宏观支撑整体偏弱。")
        case (.neutral, .tailwind):
            combinedPatternLabel = L10n.tr("短平长强")
            combinedSummary = L10n.tr("短期交投热度适中、多空力量相对均衡，同时长期美债与央行购金等宏观指标整体偏强。")
        case (.neutral, .neutral):
            combinedPatternLabel = L10n.tr("双端中性")
            combinedSummary = L10n.tr("短期交易热度与长期宏观背景均处于近 3 年中位常态，市场多空与基本面力量相对均衡。")
        case (.neutral, .headwind):
            combinedPatternLabel = L10n.tr("短平长弱")
            combinedSummary = L10n.tr("短期交投热度适中、多空力量均衡，但长期实际利率等宏观指标支撑相对偏弱。")
        case (.warm, .tailwind):
            combinedPatternLabel = L10n.tr("短热长强")
            combinedSummary = L10n.tr("短期交投升温、资金关注度偏高，同时长期美债与央行购金等宏观支撑偏强，短长周期同步偏强。")
        case (.warm, .neutral):
            combinedPatternLabel = L10n.tr("短热长平")
            combinedSummary = L10n.tr("短期交投偏热、资金关注度处于近 3 年偏高分位，而长期宏观基本面整体处于中性常态。")
        case (.warm, .headwind):
            combinedPatternLabel = L10n.tr("短热长弱")
            combinedSummary = L10n.tr("短期交投偏热、资金关注度升温，但长期宏观指标支撑偏弱，短长周期呈现错位特征。")
        case (.hot, .tailwind):
            combinedPatternLabel = L10n.tr("过热长强")
            combinedSummary = L10n.tr("短期交投过热、多头拥挤度处于近 3 年高位，虽有长期宏观支撑偏强，历史同期短期振幅往往放大。")
        case (.hot, .neutral):
            combinedPatternLabel = L10n.tr("过热长平")
            combinedSummary = L10n.tr("短期交投过热、多头拥挤度处于近 3 年高位，长期宏观背景处于中性常态，历史同期短期波动往往放大。")
        case (.hot, .headwind):
            combinedPatternLabel = L10n.tr("过热长弱")
            combinedSummary = L10n.tr("短期交投过热、多头拥挤度处于近 3 年高位，且长期宏观支撑偏弱，短长周期明显错位，历史同期波动往往放大。")
        }

        return MacroDualHorizonSummary(
            shortTermLevel: level,
            shortTermScore: clampedShort,
            shortTermLevelLabel: level.defaultLabel,
            shortTermCompactTitle: shortCompactTitle,
            shortTermState: shortState,
            shortTermCrowding: shortCrowding,
            shortTermPlainNote: shortPlainNote,
            shortTermDetailNote: shortDetailNote,
            longTermRegime: regime,
            longTermScore: clampedLong,
            longTermScoreText: longScoreText,
            longTermState: longState,
            longTermPlainNote: longPlainNote,
            longTermDetailNote: longDetailNote,
            combinedPatternLabel: combinedPatternLabel,
            combinedSummary: combinedSummary
        )
    }

    static func objectiveStatusLabel(for level: MacroTemperatureLevel) -> String {
        switch level {
        case .freezing: L10n.tr("近3年极低分位")
        case .cool: L10n.tr("拥挤度较低")
        case .neutral: L10n.tr("热度均衡")
        case .warm: L10n.tr("关注度偏高")
        case .hot: L10n.tr("拥挤度偏高")
        }
    }

    /// 优先使用服务端下发的客观标签；若旧版服务端仍返回含投顾/定投字样或处于非中文语言环境，则前端兜底映射为本地化客观历史分位标签。
    static func objectiveStatusBadge(for guide: MacroActionGuide, level: MacroTemperatureLevel) -> String {
        let trimmed = guide.dcaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        return objectiveStatusLabel(for: level)
    }

    static func objectiveGuideTitle(for report: MacroTemperatureReport) -> String {
        let trimmed = report.actionGuide.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        let levelPart = report.level.defaultLabel
        let regimePart = report.macroRegime.regime.defaultLabel
        switch report.level {
        case .freezing: return L10n.fmt("%@ · 热度处于低位", levelPart)
        case .cool: return L10n.fmt("%@ · %@", levelPart, regimePart)
        case .neutral: return L10n.fmt("%@ · 多空相对均衡", levelPart)
        case .warm: return L10n.fmt("%@ · 关注度升温", levelPart)
        case .hot: return L10n.fmt("%@ · 交易高度拥挤", levelPart)
        }
    }

    static func objectiveGuideSummary(for report: MacroTemperatureReport) -> String {
        let trimmed = report.actionGuide.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        let regimeSummary: String
        switch report.macroRegime.regime {
        case .tailwind: regimeSummary = L10n.tr("长期宏观支撑偏强")
        case .neutral: regimeSummary = L10n.tr("长期宏观底座处于中性")
        case .headwind: regimeSummary = L10n.tr("长期宏观底座偏弱")
        }
        switch report.level {
        case .freezing:
            return L10n.fmt("五维市场热度处于近 3 年极低分位，市场关注度低迷；%@。", regimeSummary)
        case .cool:
            return L10n.fmt("五维市场热度处于近 3 年偏低分位，交易拥挤度较低；%@。", regimeSummary)
        case .neutral:
            return L10n.fmt("五维市场热度处于近 3 年中位区间，多空力量相对均衡；%@。", regimeSummary)
        case .warm:
            return L10n.fmt("五维市场热度处于近 3 年偏高分位，资金关注度升温；%@。", regimeSummary)
        case .hot:
            return L10n.fmt("五维市场热度处于近 3 年高位，短期偏离与多头拥挤度偏高；%@。", regimeSummary)
        }
    }

    static func objectiveMa200Note(for guide: MacroActionGuide) -> String {
        let trimmed = guide.ma200Note.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        guard let dev = guide.ma200DeviationPct, dev.isFinite else {
            return L10n.tr("暂无 200 日均线偏离统计")
        }
        if dev > 0.05 {
            return L10n.fmt("高于 200 日均线 %@，处于年线上方", "\(String(format: "%.2f", dev))%")
        } else if dev < -0.05 {
            return L10n.fmt("低于 200 日均线 %@，处于年线下方", "\(String(format: "%.2f", abs(dev)))%")
        } else {
            return L10n.tr("接近 200 日均线位置")
        }
    }

    static func objectiveDomesticPremiumNote(for guide: MacroActionGuide) -> String {
        let trimmed = guide.domesticPremiumNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        guard let premium = guide.domesticPremiumPct, premium.isFinite else {
            return L10n.tr("暂无上海金溢价统计")
        }
        if premium > 0.05 {
            return L10n.fmt("国内金价较国际溢价 %@", "+\(String(format: "%.2f", premium))%")
        } else if premium < -0.05 {
            return L10n.fmt("国内金价较国际折价 %@", "\(String(format: "%.2f", premium))%")
        } else {
            return L10n.tr("国内与国际金价基本平水")
        }
    }

    static func objectiveVolatilityNote(for report: MacroTemperatureReport) -> String {
        let trimmed = report.volatilityNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty && !containsAdvisoryTerms(trimmed) {
            return trimmed
        }
        if !MacroLocalization.isChinese {
            if report.volatilityAlert {
                return L10n.tr("黄金隐含波动率处于近 3 年偏高分位，历史同期短期振幅往往放大。")
            }
            if !report.hasAvailableData {
                return L10n.tr("波动率指标尚未同步，暂无法评估当前市场波动水平。")
            }
            return L10n.tr("黄金隐含波动率处于常态区间，暂无高波动提示。")
        }
        return L10n.tr("黄金隐含波动率处于近 3 年偏高分位，历史同期短期振幅往往放大。")
    }

    static func objectiveDisclaimer(for guide: MacroActionGuide) -> String {
        let trimmed = guide.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines)
        if MacroLocalization.isChinese && !trimmed.isEmpty {
            return trimmed
        }
        return defaultDisclaimer
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
        return L10n.fmt("%@ 万亿", "\(sign)$\(String(format: "%.2f", abs(value)))")
    }

    static func formatContracts(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let absVal = abs(value)
        let prefix = signPrefix(for: value, signed: signed)
        if MacroLocalization.usesTenThousandScale {
            if absVal >= 10_000 {
                return L10n.fmt("%@ 万手", "\(prefix)\(String(format: "%.2f", absVal / 10_000))")
            }
            return L10n.fmt("%@ 手", "\(prefix)\(Int(absVal.rounded()))")
        } else {
            if absVal >= 1_000 {
                return L10n.fmt("%@k 手", "\(prefix)\(String(format: "%.1f", absVal / 1_000))")
            }
            return L10n.fmt("%@ 手", "\(prefix)\(Int(absVal.rounded()))")
        }
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
            return L10n.fmt("%@ 万亿", "\(sign)$\(String(format: "%.2f", absVal))")
        case "billion_usd", "usd_billion":
            if absVal >= 1_000 {
                return L10n.fmt("%@ 万亿", "\(sign)$\(String(format: "%.2f", absVal / 1_000))")
            }
            return "\(sign)$\(String(format: "%.1f", absVal))B"
        case "million_usd", "usd_million":
            if absVal >= 1_000_000 {
                return L10n.fmt("%@ 万亿", "\(sign)$\(String(format: "%.2f", absVal / 1_000_000))")
            }
            if absVal >= 1_000 {
                return "\(sign)$\(String(format: "%.1f", absVal / 1_000))B"
            }
            return "\(sign)$\(String(format: "%.1f", absVal))M"
        case "tons", "tonnes":
            return L10n.fmt("%@ 吨", String(format: "%.1f", value))
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
            return L10n.fmt("%@ 万亿", "\(sign)\(String(format: "%.2f", absVal))")
        case "billion_usd", "usd_billion":
            if absVal >= 1_000 {
                return L10n.fmt("%@ 万亿", "\(sign)\(String(format: "%.2f", absVal / 1_000))")
            }
            return "\(sign)\(String(format: "%.1f", absVal))B"
        case "million_usd", "usd_million":
            if absVal >= 1_000_000 {
                return L10n.fmt("%@ 万亿", "\(sign)\(String(format: "%.2f", absVal / 1_000_000))")
            }
            if absVal >= 1_000 {
                return "\(sign)\(String(format: "%.1f", absVal / 1_000))B"
            }
            return "\(sign)\(String(format: "%.1f", absVal))M"
        case "tons", "tonnes":
            return L10n.fmt("%@ 吨", "\(sign)\(String(format: "%.1f", absVal))")
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
        guard let value, value.isFinite else { return L10n.tr("分位待积累") }
        let clamped = min(max(value, 0), 100)
        let tier: String
        switch clamped {
        case ..<20: tier = L10n.tr("极低位")
        case 20..<40: tier = L10n.tr("偏低位")
        case 40..<60: tier = L10n.tr("中位区")
        case 60..<80: tier = L10n.tr("偏高位")
        default: tier = L10n.tr("极高位")
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
