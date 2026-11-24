import Foundation

// MARK: - 小组件口径与客观语义模型

/// 小组件可选行情口径（与主 App `GoldMarketBasis` 保持 1:1 语义一致）。
enum GoldWidgetBasis: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case domestic = "au9999"
    case international = "xauusd"

    var id: String { rawValue }

    var instrumentID: String { rawValue }

    var displayName: String {
        switch self {
        case .domestic: L10n.tr("国内 Au99.99")
        case .international: L10n.tr("国际伦敦金")
        }
    }

    var compactTitle: String {
        switch self {
        case .domestic: L10n.tr("国内金价")
        case .international: L10n.tr("伦敦金")
        }
    }

    var symbolBadge: String {
        switch self {
        case .domestic: "AU99.99"
        case .international: "XAUUSD"
        }
    }

    var quotePath: String {
        "app/market/gold/instruments/\(instrumentID)/quote"
    }

    var dailyPath: String {
        "app/market/gold/instruments/\(instrumentID)/daily"
    }
}

/// 短期黄金温度区间（0~100°），全部使用纯客观状态文案，不含任何投顾措辞。
enum GoldWidgetTemperatureLevel: String, Codable, Sendable, CaseIterable, Hashable {
    case freezing
    case cool
    case neutral
    case warm
    case hot

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self = GoldWidgetTemperatureLevel(rawValue: raw) ?? .neutral
    }

    static func from(score: Double) -> GoldWidgetTemperatureLevel {
        guard score.isFinite else { return .neutral }
        switch score {
        case ..<20: return .freezing
        case 20..<40: return .cool
        case 40..<60: return .neutral
        case 60..<80: return .warm
        default: return .hot
        }
    }

    /// 短标签（用于小号/中号/锁屏小组件徽章）。
    var shortLabel: String {
        switch self {
        case .freezing: L10n.tr("极冷")
        case .cool: L10n.tr("偏冷")
        case .neutral: L10n.tr("中性")
        case .warm: L10n.tr("偏热")
        case .hot: L10n.tr("过热")
        }
    }
}

/// 长期宏观背景状态，纯客观映射，不透传旧版服务端文案。
enum GoldWidgetMacroRegime: String, Codable, Sendable, CaseIterable, Hashable {
    case tailwind
    case neutral
    case headwind

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self = GoldWidgetMacroRegime(rawValue: raw) ?? .neutral
    }

    /// 纯客观宏观状态标签（与主 App `MacroRegimeKind.defaultLabel` 一致）。
    var shortLabel: String {
        switch self {
        case .tailwind: L10n.tr("支撑偏强")
        case .neutral: L10n.tr("背景中性")
        case .headwind: L10n.tr("支撑偏弱")
        }
    }
}

/// 黄金温度计精简快照（供小组件直接渲染）。
struct GoldWidgetTemperatureSnapshot: Codable, Sendable, Equatable {
    let score: Double
    let level: GoldWidgetTemperatureLevel
    let regime: GoldWidgetMacroRegime
    let asOf: String

    var clampedScore: Double {
        guard score.isFinite else { return 50 }
        return min(max(score, 0), 100)
    }

    var roundedDegree: Int {
        Int(clampedScore.rounded())
    }

    var degreeText: String {
        "\(roundedDegree)°"
    }

    /// 例：`27° 偏冷`
    var shortBadgeText: String {
        "\(roundedDegree)° \(level.shortLabel)"
    }

    /// 例：`27° 偏冷 · 支撑偏强`
    var dualHorizonText: String {
        "\(roundedDegree)° \(level.shortLabel) · \(regime.shortLabel)"
    }
}

/// 近一月日线走势点（统一折算为人民币/克）。
struct GoldWidgetPricePoint: Codable, Sendable, Equatable {
    let date: String
    let priceCNY: Double
}

/// 脱敏持有摘要（仅在 App Group 可用时由主 App 写入，不保存账户/金额等敏感信息）。
struct GoldWidgetHoldingsSummary: Codable, Sendable, Equatable {
    let totalGrams: Double
    let updatedAt: Date
}

/// 涨跌方向（遵守国内习惯：红涨绿跌）。
enum GoldWidgetTrendDirection: Sendable, Equatable {
    case up
    case down
    case flat

    static func resolve(changeCNY: Double?, changePercent: Double?) -> GoldWidgetTrendDirection {
        let signal = changeCNY ?? changePercent
        guard let signal, signal.isFinite else { return .flat }
        if signal > 0.0001 { return .up }
        if signal < -0.0001 { return .down }
        return .flat
    }

    var arrowSymbol: String {
        switch self {
        case .up: "▲"
        case .down: "▼"
        case .flat: "—"
        }
    }
}

/// 单个口径的完整小组件行情与温度快照。
struct GoldWidgetSnapshot: Codable, Sendable, Equatable {
    let basis: GoldWidgetBasis
    let cnyPerGram: Double
    let changeCNY: Double?
    let changePercent: Double?
    let usdPerOz: Double?
    let asOf: Date
    let fetchedAt: Date
    let recentSeries: [GoldWidgetPricePoint]
    let temperature: GoldWidgetTemperatureSnapshot?
    let isCachedFallback: Bool

    var hasValidPrice: Bool {
        cnyPerGram.isFinite && cnyPerGram > 0
    }

    var trendDirection: GoldWidgetTrendDirection {
        GoldWidgetTrendDirection.resolve(changeCNY: changeCNY, changePercent: changePercent)
    }

    /// 走势图序列（附带当前最新克价尾点以反映盘中变化）。
    var sparklineValues: [Double] {
        var values = recentSeries.map(\.priceCNY).filter { $0.isFinite && $0 > 0 }
        if hasValidPrice {
            if let last = values.last {
                if abs(last - cnyPerGram) > 0.0001 {
                    values.append(cnyPerGram)
                }
            } else {
                values = [cnyPerGram]
            }
        }
        return values
    }

    var rangeHighCNY: Double? {
        sparklineValues.max()
    }

    var rangeLowCNY: Double? {
        sparklineValues.min()
    }

    func markingCachedFallback() -> GoldWidgetSnapshot {
        GoldWidgetSnapshot(
            basis: basis,
            cnyPerGram: cnyPerGram,
            changeCNY: changeCNY,
            changePercent: changePercent,
            usdPerOz: usdPerOz,
            asOf: asOf,
            fetchedAt: fetchedAt,
            recentSeries: recentSeries,
            temperature: temperature,
            isCachedFallback: true
        )
    }

    /// 仅用于 WidgetKit `placeholder` 与组件库预览，网络失败时严禁降级使用本示例数据。
    static func previewPlaceholder(basis: GoldWidgetBasis = .domestic) -> GoldWidgetSnapshot {
        let baseDate = Date(timeIntervalSince1970: 1_795_200_000)
        let sampleCloses: [Double] = [
            742.5, 748.2, 745.8, 752.4, 758.0, 761.5, 756.9, 764.2,
            772.0, 779.4, 775.1, 783.6, 791.2, 798.5, 804.0, 799.2,
            811.4, 818.6, 825.0, 832.5, 821.8, 810.8, 801.9, 788.4,
            776.2, 764.6
        ]
        let series = sampleCloses.enumerated().map { index, close in
            GoldWidgetPricePoint(
                date: String(format: "2026-11-%02d", min(index + 1, 28)),
                priceCNY: basis == .domestic ? close : close + 2.8
            )
        }
        let price = basis == .domestic ? 755.01 : 758.20
        let change = basis == .domestic ? -9.54 : -19.37
        let pct = basis == .domestic ? -1.25 : -2.49
        return GoldWidgetSnapshot(
            basis: basis,
            cnyPerGram: price,
            changeCNY: change,
            changePercent: pct,
            usdPerOz: basis == .international ? 3534.64 : nil,
            asOf: baseDate,
            fetchedAt: baseDate,
            recentSeries: series,
            temperature: GoldWidgetTemperatureSnapshot(
                score: 27.3,
                level: .cool,
                regime: .tailwind,
                asOf: "2026-11-20"
            ),
            isCachedFallback: false
        )
    }
}

// MARK: - 格式化纯函数

enum GoldWidgetFormatting {
    static func formatPriceCNY(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "--" }
        return String(format: "%.2f", value)
    }

    static func formatCompactPriceCNY(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "--" }
        return String(format: "%.1f", value)
    }

    static func formatIntegerPriceCNY(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "--" }
        return "\(Int(value.rounded()))"
    }

    static func formatSignedChangeCNY(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        if abs(value) < 0.005 { return "0.00" }
        let prefix = value > 0 ? "+" : "-"
        return "\(prefix)\(String(format: "%.2f", abs(value)))"
    }

    static func formatSignedPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        if abs(value) < 0.005 { return "0.00%" }
        let prefix = value > 0 ? "+" : "-"
        return "\(prefix)\(String(format: "%.2f", abs(value)))%"
    }

    static func formatCompactChange(changeCNY: Double?, changePercent: Double?) -> String {
        let changeText = formatSignedChangeCNY(changeCNY)
        let pctText = formatSignedPercent(changePercent)
        if changeText == "--" && pctText == "--" {
            return L10n.tr("暂无涨跌")
        }
        return "\(changeText) (\(pctText))"
    }

    static func formatUSDPerOz(_ value: Double?) -> String? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return "$\(String(format: "%.0f", value))/oz"
    }

    static func formatUpdatedTime(
        _ date: Date,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        compact: Bool = false
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = compact ? "MM/dd" : "MM/dd HH:mm"
        }
        return formatter.string(from: date)
    }
}

// MARK: - 轻量 Sparkline 采样与归一化

enum GoldWidgetSparkline {
    struct NormalizedPoint: Sendable, Equatable {
        /// 归一化横坐标（0...1）。
        let x: Double
        /// 归一化纵坐标（0...1，0 为区间最低、1 为区间最高）。
        let y: Double
    }

    /// 过滤异常点、均匀采样（保留首尾）并归一化到 0...1。
    static func sampleAndNormalize(_ rawValues: [Double], maxPoints: Int = 30) -> [NormalizedPoint] {
        let valid = rawValues.filter { $0.isFinite && $0 > 0 }
        guard !valid.isEmpty else { return [] }
        if valid.count == 1 {
            return [
                NormalizedPoint(x: 0, y: 0.5),
                NormalizedPoint(x: 1, y: 0.5)
            ]
        }

        let targetCount = max(2, maxPoints)
        let sampled: [Double]
        if valid.count <= targetCount {
            sampled = valid
        } else {
            let lastIndex = valid.count - 1
            sampled = (0..<targetCount).map { idx in
                let position = Double(idx) * Double(lastIndex) / Double(targetCount - 1)
                return valid[Int(position.rounded())]
            }
        }

        guard let minValue = sampled.min(), let maxValue = sampled.max() else {
            return []
        }
        let span = maxValue - minValue
        let denominator = Double(max(sampled.count - 1, 1))

        return sampled.enumerated().map { idx, value in
            let x = Double(idx) / denominator
            let y: Double = span > 1e-9 ? (value - minValue) / span : 0.5
            return NormalizedPoint(x: x, y: min(max(y, 0), 1))
        }
    }
}

// MARK: - 网络层（独立直连线上只读 API，纯 Sendable）

struct GoldWidgetAPIClient: Sendable {
    static let defaultBaseURL = URL(string: "https://oryjk.cn/sumly/api/v1")!
    static let gramsPerTroyOunce = 31.1034768

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = GoldWidgetAPIClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    enum ClientError: Error, Equatable, Sendable {
        case badResponse
        case httpStatus(Int)
        case envelope(Int, String)
        case emptyData
        case malformedPayload
    }

    struct DecodedQuote: Sendable, Equatable {
        let basis: GoldWidgetBasis
        let cnyPerGram: Double
        let changeCNY: Double?
        let changePercent: Double?
        let usdPerOz: Double?
        let conversionRatio: Double
        let asOf: Date
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: T?
    }

    private struct QuoteDTO: Decodable {
        let symbol: String?
        let price: Double
        let open: Double?
        let high: Double?
        let low: Double?
        let prevClose: Double?
        let usdCNY: Double?
        let cnyPerGram: Double
        let asOf: String

        enum CodingKeys: String, CodingKey {
            case symbol, price, open, high, low
            case prevClose = "prev_close"
            case usdCNY = "usd_cny"
            case cnyPerGram = "cny_per_gram"
            case asOf = "as_of"
        }
    }

    private struct DailyDTO: Decodable {
        struct Bar: Decodable {
            let date: String
            let close: Double
        }
        let unit: String?
        let bars: [Bar]
    }

    private struct TemperatureDTO: Decodable {
        struct RegimeDTO: Decodable {
            let score: Double?
            let regime: GoldWidgetMacroRegime?
        }
        let asOf: String?
        let score: Double
        let level: GoldWidgetTemperatureLevel?
        let macroRegime: RegimeDTO?

        enum CodingKeys: String, CodingKey {
            case score, level
            case asOf = "as_of"
            case macroRegime = "macro_regime"
        }
    }

    // MARK: - 实时拉取（报价必选，日线与温度并发最佳努力获取）

    func fetchSnapshot(for basis: GoldWidgetBasis, now: Date = Date()) async throws -> GoldWidgetSnapshot {
        async let quoteData = getData(path: basis.quotePath)
        async let dailyData: Data? = try? await getData(path: basis.dailyPath)
        async let tempData: Data? = try? await getData(path: "app/macro/temperature")

        let decodedQuote = try Self.decodeQuote(from: try await quoteData, basis: basis)
        let dailySeries: [GoldWidgetPricePoint]
        if let rawDaily = await dailyData {
            dailySeries = (try? Self.decodeDailySeries(
                from: rawDaily,
                basis: basis,
                conversionRatio: decodedQuote.conversionRatio,
                limit: 30
            )) ?? []
        } else {
            dailySeries = []
        }

        let temperature: GoldWidgetTemperatureSnapshot?
        if let rawTemp = await tempData {
            temperature = try? Self.decodeTemperature(from: rawTemp)
        } else {
            temperature = nil
        }

        return Self.assembleSnapshot(
            quote: decodedQuote,
            dailySeries: dailySeries,
            temperature: temperature,
            fetchedAt: now
        )
    }

    // MARK: - 纯函数解码（供单测直接覆盖）

    static func decodeQuote(from data: Data, basis: GoldWidgetBasis) throws -> DecodedQuote {
        let dto = try decodeEnvelope(QuoteDTO.self, from: data)
        guard dto.cnyPerGram.isFinite, dto.cnyPerGram > 0,
              let asOf = parseRFC3339(dto.asOf) else {
            throw ClientError.malformedPayload
        }

        let ratio: Double
        switch basis {
        case .domestic:
            ratio = 1
        case .international:
            if dto.price.isFinite, dto.price > 0 {
                ratio = dto.cnyPerGram / dto.price
            } else if let usdCNY = dto.usdCNY, usdCNY.isFinite, usdCNY > 0 {
                ratio = usdCNY / gramsPerTroyOunce
            } else {
                ratio = 0
            }
        }

        let prevCloseCNY: Double? = {
            guard let prev = dto.prevClose, prev.isFinite, prev > 0, ratio > 0 else { return nil }
            let converted = prev * ratio
            return converted.isFinite && converted > 0 ? converted : nil
        }()

        let changeCNY = prevCloseCNY.map { dto.cnyPerGram - $0 }
        let changePercent: Double? = {
            guard let prevCloseCNY, prevCloseCNY > 0, let changeCNY else { return nil }
            return changeCNY / prevCloseCNY * 100
        }()

        let usdPerOz: Double? = (basis == .international && dto.price.isFinite && dto.price > 0)
            ? dto.price
            : nil

        return DecodedQuote(
            basis: basis,
            cnyPerGram: dto.cnyPerGram,
            changeCNY: changeCNY,
            changePercent: changePercent,
            usdPerOz: usdPerOz,
            conversionRatio: ratio,
            asOf: asOf
        )
    }

    static func decodeDailySeries(
        from data: Data,
        basis: GoldWidgetBasis,
        conversionRatio: Double,
        limit: Int = 30
    ) throws -> [GoldWidgetPricePoint] {
        let dto = try decodeEnvelope(DailyDTO.self, from: data)
        let normalizedUnit = dto.unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let needsConversion: Bool
        if normalizedUnit.contains("usd") {
            needsConversion = true
        } else if normalizedUnit.contains("cny") {
            needsConversion = false
        } else {
            needsConversion = (basis == .international)
        }

        let factor = needsConversion ? conversionRatio : 1
        guard factor.isFinite, factor > 0 else { return [] }

        let validBars = dto.bars
            .filter { !$0.date.isEmpty && $0.close.isFinite && $0.close > 0 }
            .sorted { $0.date < $1.date }

        guard !validBars.isEmpty else {
            throw ClientError.emptyData
        }

        let slice = validBars.suffix(max(2, limit))
        return slice.map { bar in
            GoldWidgetPricePoint(date: bar.date, priceCNY: bar.close * factor)
        }
    }

    static func decodeTemperature(from data: Data) throws -> GoldWidgetTemperatureSnapshot {
        let dto = try decodeEnvelope(TemperatureDTO.self, from: data)
        let trimmedAsOf = dto.asOf?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedAsOf.isEmpty, dto.score.isFinite else {
            throw ClientError.emptyData
        }
        let clamped = min(max(dto.score, 0), 100)
        let level = dto.level ?? GoldWidgetTemperatureLevel.from(score: clamped)
        let regime = dto.macroRegime?.regime ?? .neutral
        return GoldWidgetTemperatureSnapshot(
            score: clamped,
            level: level,
            regime: regime,
            asOf: trimmedAsOf
        )
    }

    static func assembleSnapshot(
        quote: DecodedQuote,
        dailySeries: [GoldWidgetPricePoint],
        temperature: GoldWidgetTemperatureSnapshot?,
        fetchedAt: Date = Date()
    ) -> GoldWidgetSnapshot {
        GoldWidgetSnapshot(
            basis: quote.basis,
            cnyPerGram: quote.cnyPerGram,
            changeCNY: quote.changeCNY,
            changePercent: quote.changePercent,
            usdPerOz: quote.usdPerOz,
            asOf: quote.asOf,
            fetchedAt: fetchedAt,
            recentSeries: dailySeries,
            temperature: temperature,
            isCachedFallback: false
        )
    }

    static func parseRFC3339(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }

    private static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw ClientError.envelope(envelope.code, envelope.message ?? "")
        }
        guard let payload = envelope.data else {
            throw ClientError.emptyData
        }
        return payload
    }

    private func getData(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpStatus(http.statusCode)
        }
        return data
    }
}

// MARK: - 共享 / 独立优雅降级缓存

/// 小组件持久化缓存：
/// - 若当前签名环境已启用 App Group（`group.com.oryjk.sumly`），自动与主 App 共享；
/// - 若未配置 App Group（如尚未开通能力的 Profile 或模拟器环境），静默优雅降级为 `.standard`，不崩溃、不产生系统告警。
final class GoldWidgetCacheStore: @unchecked Sendable {
    static let appGroupIdentifier = "group.com.oryjk.sumly"
    static let shared = GoldWidgetCacheStore()

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(
        defaults: UserDefaults = GoldWidgetCacheStore.resolveUserDefaults(),
        keyPrefix: String = "com.oryjk.sumly.widget"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    static func resolveUserDefaults(suiteName: String = appGroupIdentifier) -> UserDefaults {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) != nil,
           let sharedDefaults = UserDefaults(suiteName: suiteName) {
            return sharedDefaults
        }
        return .standard
    }

    private func snapshotKey(for basis: GoldWidgetBasis) -> String {
        "\(keyPrefix).snapshot.\(basis.rawValue)"
    }

    private var holdingsKey: String {
        "\(keyPrefix).holdings_summary"
    }

    func saveSnapshot(_ snapshot: GoldWidgetSnapshot) {
        guard snapshot.hasValidPrice else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey(for: snapshot.basis))
        }
    }

    func loadSnapshot(for basis: GoldWidgetBasis) -> GoldWidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey(for: basis)),
              let snapshot = try? JSONDecoder().decode(GoldWidgetSnapshot.self, from: data),
              snapshot.hasValidPrice else {
            return nil
        }
        return snapshot
    }

    func saveHoldingsSummary(_ summary: GoldWidgetHoldingsSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            defaults.set(data, forKey: holdingsKey)
        }
    }

    func loadHoldingsSummary() -> GoldWidgetHoldingsSummary? {
        guard let data = defaults.data(forKey: holdingsKey),
              let summary = try? JSONDecoder().decode(GoldWidgetHoldingsSummary.self, from: data) else {
            return nil
        }
        return summary
    }

    func clearAll() {
        for basis in GoldWidgetBasis.allCases {
            defaults.removeObject(forKey: snapshotKey(for: basis))
        }
        defaults.removeObject(forKey: holdingsKey)
    }
}

// MARK: - 小组件快照协调服务（线上拉取 + 离线缓存降级）

protocol GoldWidgetFetching: Sendable {
    func fetchSnapshot(for basis: GoldWidgetBasis, now: Date) async throws -> GoldWidgetSnapshot
}

extension GoldWidgetAPIClient: GoldWidgetFetching {}

struct GoldWidgetSnapshotService: Sendable {
    static let shared = GoldWidgetSnapshotService()

    /// 正常刷新间隔：15 分钟。
    static let refreshIntervalSeconds: TimeInterval = 15 * 60
    /// 冷启动且网络失败时的重试间隔：5 分钟。
    static let retryIntervalSeconds: TimeInterval = 5 * 60

    let fetcher: any GoldWidgetFetching
    let cache: GoldWidgetCacheStore

    init(
        fetcher: any GoldWidgetFetching = GoldWidgetAPIClient(),
        cache: GoldWidgetCacheStore = .shared
    ) {
        self.fetcher = fetcher
        self.cache = cache
    }

    func cachedSnapshot(for basis: GoldWidgetBasis) -> GoldWidgetSnapshot? {
        cache.loadSnapshot(for: basis)?.markingCachedFallback()
    }

    /// 优先拉取线上最新快照并写缓存；网络失败时自动保留最近一次有效缓存，绝不编造假数据。
    func loadSnapshot(for basis: GoldWidgetBasis, now: Date = Date()) async -> GoldWidgetSnapshot? {
        do {
            let live = try await fetcher.fetchSnapshot(for: basis, now: now)
            if live.hasValidPrice {
                cache.saveSnapshot(live)
                return live
            }
        } catch {
            // 静默降级至本地最近有效快照。
        }
        return cache.loadSnapshot(for: basis)?.markingCachedFallback()
    }

    func nextRefreshDate(from now: Date, snapshot: GoldWidgetSnapshot?) -> Date {
        let interval = snapshot == nil ? Self.retryIntervalSeconds : Self.refreshIntervalSeconds
        return now.addingTimeInterval(interval)
    }
}
