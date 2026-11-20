import Foundation
import Testing
@testable import Sumly

// MARK: - URL 契约测试

@Test func macroServiceBuildsExactPathsAndQueries() throws {
    let base = URL(string: "https://oryjk.cn/sumly/api/v1")!

    #expect(try BackendMacroService.temperatureURL(baseURL: base).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/temperature")
    #expect(try BackendMacroService.temperatureHistoryURL(baseURL: base, range: .threeYears).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/temperature/history?range=3y")
    #expect(try BackendMacroService.treasuryURL(baseURL: base, range: .tenYears).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/treasury?range=10y")
    #expect(try BackendMacroService.indicatorsURL(baseURL: base, section: nil).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/indicators")
    #expect(try BackendMacroService.indicatorsURL(baseURL: base, section: "treasury_fiscal").absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/indicators?section=treasury_fiscal")
    #expect(try BackendMacroService.indicatorDetailURL(baseURL: base, seriesID: "DFII10", range: .fiveYears).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/indicators/DFII10?range=5y")
    #expect(try BackendMacroService.goldCotURL(baseURL: base, range: .oneYear).absoluteString ==
        "https://oryjk.cn/sumly/api/v1/app/macro/cot/gold?range=1y")

    #expect(throws: BackendMacroService.ServiceError.invalidURL) {
        _ = try BackendMacroService.indicatorDetailURL(baseURL: base, seriesID: "   ", range: .oneYear)
    }
}

// MARK: - Envelope & 6 接口契约解码测试

@Test func decodesTemperatureEnvelopeIncludingDegradedAndVolatilityAlert() throws {
    let json = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "as_of": "2026-11-20",
        "model_version": "v1",
        "degraded": true,
        "missing_factors": ["domestic_premium"],
        "score": 71.6,
        "level": "warm",
        "level_label": "偏热活跃",
        "change_1d": 1.8,
        "change_5d": -2.4,
        "volatility_alert": true,
        "volatility_note": "黄金波动率处于近3年高位，建议分批操作。",
        "macro_regime": {
          "score": 74.2,
          "regime": "tailwind",
          "label": "长期宏观顺风",
          "summary": "美债高企叠加央行购金，中长期支撑稳固。"
        },
        "action_guide": {
          "signal": "reduce_pace",
          "title": "顺风偏热，放慢节奏",
          "summary": "长期顺风但短期偏热，定投减半、不追高。",
          "dca_multiplier": 0.5,
          "dca_label": "减半定投",
          "ma200_deviation_pct": 14.35,
          "ma200_note": "高于200日均线14.35%，短期安全垫偏薄。",
          "domestic_premium_pct": 0.42,
          "domestic_premium_note": "国内金价小幅溢价，处于正常区间。",
          "disclaimer": "仅供数据参考，不构成投资建议。"
        },
        "dimensions": [
          {
            "key": "trend_momentum",
            "name": "趋势与动量",
            "weight": 0.30,
            "score": 78.5,
            "available": true,
            "status": "warm",
            "summary": "价格显著站上年线",
            "metrics": {"ma200_dev": 14.35, "rsi14": 65.2}
          },
          {
            "key": "domestic_premium",
            "name": "国内金价溢价",
            "weight": 0.15,
            "score": 0,
            "available": false,
            "status": "missing",
            "summary": "暂无数据",
            "metrics": {}
          }
        ]
      }
    }
    """

    let report = try BackendMacroService.decodeEnvelope(MacroTemperatureReport.self, from: Data(json.utf8))
    #expect(report.asOf == "2026-11-20")
    #expect(report.hasAvailableData)
    #expect(report.degraded)
    #expect(report.missingFactors == ["domestic_premium"])
    #expect(report.score == 71.6)
    #expect(report.level == .warm)
    #expect(report.change1d == 1.8)
    #expect(report.change5d == -2.4)
    #expect(report.volatilityAlert)
    #expect(report.macroRegime.regime == .tailwind)
    #expect(report.actionGuide.dcaMultiplier == 0.5)
    #expect(report.actionGuide.ma200DeviationPct == 14.35)
    #expect(report.dimensions.count == 2)
    #expect(report.dimensions[0].metrics["rsi14"] == 65.2)
    #expect(report.dimensions[1].available == false)

    let asOfDate = try #require(report.asOfDate)
    let calendar = Calendar(identifier: .gregorian)
    #expect(calendar.component(.hour, from: asOfDate) == 12)
}

@Test func coldStartTemperatureReportsNoAvailableData() throws {
    let json = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "as_of": "",
        "model_version": "v1",
        "degraded": true,
        "missing_factors": ["trend_momentum", "positioning"],
        "score": 50.0,
        "level": "neutral",
        "level_label": "温和中性",
        "change_1d": null,
        "change_5d": null,
        "volatility_alert": false,
        "volatility_note": "",
        "macro_regime": {"score": 50, "regime": "neutral", "label": "宏观中性", "summary": ""},
        "action_guide": {
          "signal": "wait", "title": "等待同步", "summary": "", "dca_multiplier": 1.0,
          "dca_label": "正常定投", "ma200_deviation_pct": null, "ma200_note": "",
          "domestic_premium_pct": null, "domestic_premium_note": "", "disclaimer": "仅供参考"
        },
        "dimensions": [
          {"key": "trend_momentum", "name": "趋势与动量", "weight": 0.3, "score": 0, "available": false, "status": "missing", "summary": "", "metrics": {}}
        ]
      }
    }
    """
    let report = try BackendMacroService.decodeEnvelope(MacroTemperatureReport.self, from: Data(json.utf8))
    #expect(!report.hasAvailableData)
    #expect(report.asOfDate == nil)
}

@Test func decodesTemperatureHistorySortedWithNoonDates() throws {
    let json = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "range": "3y",
        "model_version": "v1",
        "points": [
          {"date": "2026-11-20", "score": 68.4, "level": "warm", "gold_price_usd": 2650.5},
          {"date": "bad-date", "score": 50.0, "level": "neutral", "gold_price_usd": 2500.0},
          {"date": "2026-11-18", "score": 32.1, "level": "cool", "gold_price_usd": null}
        ]
      }
    }
    """
    let history = try BackendMacroService.decodeEnvelope(MacroTemperatureHistory.self, from: Data(json.utf8))
    #expect(history.range == "3y")
    #expect(history.points.count == 2)
    #expect(history.points.map(\.dateString) == ["2026-11-18", "2026-11-20"])
    #expect(history.points[0].goldPriceUSD == nil)
    #expect(history.points[1].goldPriceUSD == 2650.5)
    let calendar = Calendar(identifier: .gregorian)
    #expect(history.points.allSatisfy { calendar.component(.hour, from: $0.date) == 12 })
}

@Test func decodesTreasuryAndIndicatorDetailAndCotContracts() throws {
    let treasuryJSON = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "as_of": "2026-11-20",
        "summary": {
          "total_debt_trillion_usd": 36.21,
          "debt_change_yoy_trillion": 2.15,
          "debt_to_gdp_pct": 122.8,
          "interest_to_revenue_pct": 18.4,
          "fiscal_stress_score": 76.5,
          "yield_10y_nominal_pct": 4.32,
          "yield_2y_nominal_pct": 4.18,
          "spread_10y_2y_pct": 0.14,
          "yield_10y_real_pct": 1.92,
          "breakeven_10y_pct": 2.40,
          "tlt_price": 91.25,
          "gold_impact_note": "高债务叠加财政付息压力抬升黄金长期配置价值。"
        },
        "cards": [
          {
            "series_id": "US_DEBT_DAILY",
            "name_zh": "美国联邦国债总额",
            "section": "treasury_fiscal",
            "unit": "trillion_usd",
            "frequency": "daily",
            "source": "US Treasury",
            "gold_relation": "positive",
            "plain_note": "美债规模持续扩张利好黄金信用对冲需求。",
            "latest_date": "2026-11-20",
            "latest_value": 36.21,
            "change_5d": 0.08,
            "change_20d": 0.22,
            "change_3m": 0.65,
            "change_yoy": 2.15,
            "percentile_3y": 100.0,
            "sparkline": [35.1, 35.6, 36.21]
          }
        ],
        "debt_series": [{"date": "2026-11-19", "value": 36.18}, {"date": "2026-11-20", "value": 36.21}],
        "real_yield_series": [{"date": "2026-11-20", "value": 1.92}],
        "nominal_yield_series": [{"date": "2026-11-20", "value": 4.32}]
      }
    }
    """
    let treasury = try BackendMacroService.decodeEnvelope(MacroTreasuryReport.self, from: Data(treasuryJSON.utf8))
    #expect(treasury.hasAnyData)
    #expect(treasury.summary.totalDebtTrillionUSD == 36.21)
    #expect(treasury.summary.spread10y2yPct == 0.14)
    #expect(treasury.cards.count == 1)
    #expect(treasury.debtSeries.count == 2)

    let detailJSON = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "series_id": "DFII10",
        "name_zh": "10年期美债实际利率",
        "section": "opportunity_cost",
        "unit": "%",
        "frequency": "daily",
        "source": "FRED",
        "gold_relation": "negative",
        "plain_note": "实际利率走低时，持有无息黄金的机会成本下降。",
        "latest_date": "2026-11-20",
        "latest_value": 1.92,
        "change_5d": -0.06,
        "change_20d": -0.15,
        "change_3m": -0.22,
        "change_yoy": -0.35,
        "percentile_3y": 64.5,
        "range": "5y",
        "percentiles": [
          {"window": "1y", "percentile": 52.0, "observation_count": 250},
          {"window": "3y", "percentile": 64.5, "observation_count": 750}
        ],
        "last_synced_at": "2026-11-20T08:30:00Z",
        "sync_status": "ok",
        "observations": [
          {"date": "2026-11-20", "value": 1.92},
          {"date": "2026-11-19", "value": 1.98}
        ]
      }
    }
    """
    let detail = try BackendMacroService.decodeEnvelope(MacroIndicatorDetail.self, from: Data(detailJSON.utf8))
    #expect(detail.seriesID == "DFII10")
    #expect(detail.syncStatus == "ok")
    #expect(detail.percentiles.count == 2)
    #expect(detail.observations.map(\.dateString) == ["2026-11-19", "2026-11-20"])

    let cotJSON = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "series_id": "GOLD_COT",
        "range": "3y",
        "latest": {
          "date": "2026-11-17",
          "mm_long": 240000,
          "mm_short": 45000,
          "mm_net": 195000,
          "swap_long": 32000,
          "swap_short": 210000,
          "swap_net": -178000,
          "open_interest": 520000,
          "mm_net_ratio_pct": 37.5
        },
        "points": [
          {
            "date": "2026-11-10",
            "mm_long": 210000,
            "mm_short": 50000,
            "mm_net": 160000,
            "swap_long": 30000,
            "swap_short": 180000,
            "swap_net": -150000,
            "open_interest": 0,
            "mm_net_ratio_pct": null
          },
          {
            "date": "2026-11-17",
            "mm_long": 240000,
            "mm_short": 45000,
            "mm_net": 195000,
            "swap_long": 32000,
            "swap_short": 210000,
            "swap_net": -178000,
            "open_interest": 520000,
            "mm_net_ratio_pct": 37.5
          }
        ]
      }
    }
    """
    let cot = try BackendMacroService.decodeEnvelope(MacroCotReport.self, from: Data(cotJSON.utf8))
    #expect(cot.seriesID == "GOLD_COT")
    #expect(cot.latest?.mmNet == 195000)
    #expect(cot.points.count == 2)
    #expect(cot.points[0].mmNetRatioPct == nil)
    #expect(cot.points[1].mmNetRatioPct == 37.5)
}

@Test func envelopeRejectsNonZeroCodeAndMissingData() {
    let errJSON = #"{"code":5001,"message":"sync unavailable","data":null}"#
    #expect(throws: BackendMacroService.ServiceError.envelope(5001, "sync unavailable")) {
        _ = try BackendMacroService.decodeEnvelope(MacroIndicatorsCatalog.self, from: Data(errJSON.utf8))
    }

    let emptyJSON = #"{"code":0,"message":"ok","data":null}"#
    #expect(throws: BackendMacroService.ServiceError.emptyData) {
        _ = try BackendMacroService.decodeEnvelope(MacroIndicatorsCatalog.self, from: Data(emptyJSON.utf8))
    }
}

// MARK: - 展示与纯逻辑测试

@Test func temperatureLevelsAndFormattingLogic() {
    #expect(MacroTemperatureLevel.from(score: 12) == .freezing)
    #expect(MacroTemperatureLevel.from(score: 25) == .cool)
    #expect(MacroTemperatureLevel.from(score: 50) == .neutral)
    #expect(MacroTemperatureLevel.from(score: 72) == .warm)
    #expect(MacroTemperatureLevel.from(score: 88) == .hot)
    #expect(MacroTemperatureLevel.from(score: .nan) == .neutral)

    #expect(MacroPresentation.clampedTemperatureScore(-10) == 0)
    #expect(MacroPresentation.clampedTemperatureScore(135) == 100)
    #expect(MacroPresentation.clampedTemperatureScore(.infinity) == 0)

    // 国内红涨绿跌
    #expect(MacroPresentation.changeColor(for: 0.5) == GoldTheme.up)
    #expect(MacroPresentation.changeColor(for: -0.5) == GoldTheme.down)
    #expect(MacroPresentation.changeColor(for: 0) == GoldTheme.textSecondary)
    #expect(MacroPresentation.changeColor(for: nil) == GoldTheme.textSecondary)

    #expect(MacroPresentation.formatValue(36.21, unit: "trillion_usd") == "$36.21 万亿")
    #expect(MacroPresentation.formatValue(1.92, unit: "%") == "1.92%")
    #expect(MacroPresentation.formatValue(925.4, unit: "tons") == "925.4 吨")
    #expect(MacroPresentation.formatContracts(195_000, signed: true) == "+19.50 万手")
    #expect(MacroPresentation.formatDCAMultiplier(1.5) == "1.5x")

    #expect(MacroPresentation.normalizedSparkline([]) == [])
    #expect(MacroPresentation.normalizedSparkline([10, 10, 10]) == [0.5, 0.5, 0.5])
    #expect(MacroPresentation.normalizedSparkline([10, 20, 30]) == [0.0, 0.5, 1.0])
}

// MARK: - ViewModel 状态机与并发安全测试

private struct MacroFixtureData {
    static let sampleSummary = MacroIndicatorSummary(
        seriesID: "DFII10",
        nameZh: "10年期美债实际利率",
        section: "opportunity_cost",
        unit: "%",
        frequency: "daily",
        source: "FRED",
        goldRelation: "negative",
        plainNote: "实际利率下降利好黄金。",
        latestDate: "2026-11-20",
        latestValue: 1.85,
        change5d: -0.05,
        change20d: -0.12,
        change3m: -0.20,
        changeYoY: -0.40,
        percentile3y: 58.0,
        sparkline: [2.0, 1.95, 1.85]
    )

    static let sampleTemperature = MacroTemperatureReport(
        asOf: "2026-11-20",
        modelVersion: "v1",
        degraded: false,
        missingFactors: [],
        score: 48.5,
        level: .neutral,
        levelLabel: "温和中性",
        change1d: 0.6,
        change5d: -1.2,
        volatilityAlert: false,
        volatilityNote: "",
        macroRegime: MacroRegime(score: 68, regime: .tailwind, label: "长期宏观顺风", summary: "央行购金支撑"),
        actionGuide: MacroActionGuide(
            signal: "normal_dca",
            title: "按计划定投",
            summary: "温度温和，保持正常节奏。",
            dcaMultiplier: 1.0,
            dcaLabel: "正常定投",
            ma200DeviationPct: 8.2,
            ma200Note: "偏离温和",
            domesticPremiumPct: 0.25,
            domesticPremiumNote: "溢价合理",
            disclaimer: "仅供参考"
        ),
        dimensions: [
            MacroTemperatureDimension(key: "trend_momentum", name: "趋势与动量", weight: 0.3, score: 52, available: true, status: "neutral", summary: "温和")
        ]
    )

    static let sampleTreasury = MacroTreasuryReport(
        asOf: "2026-11-20",
        summary: MacroTreasurySummary(
            totalDebtTrillionUSD: 36.2,
            debtChangeYoYTrillion: 2.1,
            debtToGDPPct: 122.5,
            interestToRevenuePct: 18.2,
            fiscalStressScore: 74.0,
            yield10yNominalPct: 4.3,
            yield2yNominalPct: 4.1,
            spread10y2yPct: 0.2,
            yield10yRealPct: 1.85,
            breakeven10yPct: 2.45,
            tltPrice: 92.0,
            goldImpactNote: "财政压力高企支撑黄金。"
        ),
        cards: [sampleSummary],
        debtSeries: [MacroTimePoint(dateString: "2026-11-20", date: MacroDateParser.parseDay("2026-11-20")!, value: 36.2)],
        realYieldSeries: [MacroTimePoint(dateString: "2026-11-20", date: MacroDateParser.parseDay("2026-11-20")!, value: 1.85)],
        nominalYieldSeries: [MacroTimePoint(dateString: "2026-11-20", date: MacroDateParser.parseDay("2026-11-20")!, value: 4.3)]
    )

    static let sampleCatalog = MacroIndicatorsCatalog(sections: [
        MacroIndicatorSection(id: "treasury_fiscal", nameZh: "美债与财政信用", description: "美国联邦债务与财政压力", indicators: [sampleSummary]),
        MacroIndicatorSection(id: "opportunity_cost", nameZh: "利率与机会成本", description: "实际利率与美债曲线", indicators: [sampleSummary])
    ])

    static func sampleHistory(range: MacroHistoryRange) -> MacroTemperatureHistory {
        MacroTemperatureHistory(
            range: range.rawValue,
            modelVersion: "v1",
            points: [
                MacroTemperatureHistoryPoint(
                    dateString: "2026-11-20",
                    date: MacroDateParser.parseDay("2026-11-20")!,
                    score: range == .oneYear ? 33.0 : 66.0,
                    level: range == .oneYear ? .cool : .warm,
                    goldPriceUSD: 2650
                )
            ]
        )
    }

    static func sampleDetail(seriesID: String, range: MacroExtendedRange) -> MacroIndicatorDetail {
        MacroIndicatorDetail(
            seriesID: seriesID,
            nameZh: "10年期美债实际利率",
            section: "opportunity_cost",
            unit: "%",
            frequency: "daily",
            source: "FRED",
            goldRelation: "negative",
            plainNote: "实际利率下降利好黄金。",
            latestDate: "2026-11-20",
            latestValue: range == .oneYear ? 1.85 : 2.15,
            change5d: -0.05,
            change20d: -0.12,
            change3m: -0.20,
            changeYoY: -0.40,
            percentile3y: 58.0,
            range: range.rawValue,
            percentiles: [MacroPercentileWindow(window: "3y", percentile: 58.0, observationCount: 750)],
            lastSyncedAt: "2026-11-20T08:00:00Z",
            syncStatus: "ok",
            observations: [
                MacroTimePoint(dateString: "2026-11-19", date: MacroDateParser.parseDay("2026-11-19")!, value: 1.95),
                MacroTimePoint(dateString: "2026-11-20", date: MacroDateParser.parseDay("2026-11-20")!, value: range == .oneYear ? 1.85 : 2.15)
            ]
        )
    }
}

private struct MockMacroService: MacroServicing {
    var failCot = false
    var failTemperature = false

    func fetchTemperature() async throws -> MacroTemperatureReport {
        if failTemperature { throw URLError(.notConnectedToInternet) }
        return MacroFixtureData.sampleTemperature
    }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        MacroFixtureData.sampleHistory(range: range)
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        MacroFixtureData.sampleTreasury
    }

    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog {
        MacroFixtureData.sampleCatalog
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        MacroFixtureData.sampleDetail(seriesID: seriesID, range: range)
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        if failCot { throw URLError(.timedOut) }
        return MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [])
    }
}

@MainActor @Test func dashboardLoadsConcurrentlyAndIsolatesPartialFailures() async {
    let model = MacroDashboardViewModel(service: MockMacroService(failCot: true))
    await model.loadDashboard()

    #expect(model.temperature?.score == 48.5)
    #expect(model.treasury?.summary.totalDebtTrillionUSD == 36.2)
    #expect(model.catalog?.sections.count == 2)
    #expect(model.temperatureHistory?.points.count == 1)
    #expect(model.cot == nil)
    #expect(model.cotError != nil)
    #expect(model.temperatureError == nil)

    model.selectedSectionID = "treasury_fiscal"
    #expect(model.filteredSections.map(\.id) == ["treasury_fiscal"])
}

@MainActor @Test func dashboardReportsFriendlyErrorWhenTemperatureFails() async {
    let model = MacroDashboardViewModel(service: MockMacroService(failTemperature: true))
    await model.loadSummary()
    #expect(model.temperature == nil)
    #expect(model.temperatureError?.contains("网络") == true)
    #expect(model.treasury != nil)
}

private actor SuspendedDetailService: MacroServicing {
    private var pending: [MacroExtendedRange: CheckedContinuation<MacroIndicatorDetail, Error>] = [:]
    private var waiters: [MacroExtendedRange: CheckedContinuation<Void, Never>] = [:]

    func fetchTemperature() async throws -> MacroTemperatureReport { MacroFixtureData.sampleTemperature }
    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory { MacroFixtureData.sampleHistory(range: range) }
    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport { MacroFixtureData.sampleTreasury }
    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog { MacroFixtureData.sampleCatalog }
    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport { MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: []) }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        try await withCheckedThrowingContinuation { continuation in
            pending[range] = continuation
            waiters.removeValue(forKey: range)?.resume()
        }
    }

    func waitForRequest(range: MacroExtendedRange) async {
        if pending[range] != nil { return }
        await withCheckedContinuation { waiters[range] = $0 }
    }

    func resolve(range: MacroExtendedRange) {
        pending.removeValue(forKey: range)?.resume(returning: MacroFixtureData.sampleDetail(seriesID: "DFII10", range: range))
    }
}

@MainActor @Test func indicatorDetailIgnoresStaleOutOfOrderRangeResponse() async {
    let service = SuspendedDetailService()
    let model = MacroIndicatorDetailViewModel(seriesID: "DFII10", service: service)

    let slowFiveYear = Task { await model.load() }
    await service.waitForRequest(range: .fiveYears)

    let fastOneYear = Task { await model.selectRange(.oneYear) }
    await service.waitForRequest(range: .oneYear)

    // 较新的 1y 先返回，较旧的 5y 后返回，不能覆盖 1y 数据。
    await service.resolve(range: .oneYear)
    await fastOneYear.value
    #expect(model.detail?.range == "1y")
    #expect(model.latestValue == 1.85)

    await service.resolve(range: .fiveYears)
    await slowFiveYear.value
    #expect(model.detail?.range == "1y")
    #expect(model.latestValue == 1.85)
    #expect(model.periodMin?.value == 1.85)
    #expect(model.periodMax?.value == 1.95)
}
