import Foundation
import SwiftUI
import Testing
import UIKit
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
        "volatility_note": "黄金隐含波动率处于近3年91%高位，历史同期短期振幅往往放大。",
        "macro_regime": {
          "score": 74.2,
          "regime": "tailwind",
          "label": "宏观偏暖",
          "summary": "美债高企叠加央行购金，中长期宏观指标偏强。"
        },
        "action_guide": {
          "signal": "reduce_pace",
          "title": "偏热区间 · 关注度升温",
          "summary": "五维市场热度处于近3年偏高分位，资金关注度升温。",
          "dca_multiplier": 0.5,
          "dca_label": "关注度偏高",
          "ma200_deviation_pct": 14.35,
          "ma200_note": "高于200日均线14.35%，处于年线上方。",
          "domestic_premium_pct": 0.42,
          "domestic_premium_note": "国内金价较国际溢价 +0.42%，处于常态区间。",
          "disclaimer": "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
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
    #expect(report.actionGuide.dcaLabel == "关注度偏高")
    #expect(report.actionGuide.ma200DeviationPct == 14.35)
    #expect(report.guideHelp == nil)
    #expect(report.resolvedGuideHelp == .defaultGuide)
    #expect(!report.resolvedGuideHelp.hasOfficialAccount)
    #expect(report.resolvedGuideHelp.displayLevels.count == 5)
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
          "dca_label": "热度均衡", "ma200_deviation_pct": null, "ma200_note": "",
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
    #expect(MacroPresentation.formatValue(-0.5, unit: "trillion_usd") == "-$0.50 万亿")
    #expect(MacroPresentation.formatTrillionUSD(-0.5, signed: true) == "-$0.50 万亿")
    #expect(MacroPresentation.formatTrillionUSD(2.15, signed: true) == "+$2.15 万亿")
    #expect(MacroPresentation.formatValue(-1_200, unit: "billion_usd") == "-$1.20 万亿")
    #expect(MacroPresentation.formatValue(-50, unit: "billion_usd") == "-$50.0B")
    #expect(MacroPresentation.formatValue(4_900_000, unit: "million_usd") == "$4.90 万亿")
    #expect(MacroPresentation.formatValue(850_000, unit: "million_usd") == "$850.0B")
    #expect(MacroPresentation.formatValue(-450, unit: "million_usd") == "-$450.0M")
    #expect(MacroPresentation.formatDelta(1_500_000, unit: "million_usd") == "+1.50 万亿")
    #expect(MacroPresentation.formatDelta(-120_000, unit: "million_usd") == "-120.0B")
    #expect(MacroPresentation.formatDelta(-50, unit: "million_usd") == "-50.0M")
    #expect(MacroPresentation.formatValue(-12.5, unit: "usd") == "-$12.50")
    #expect(MacroPresentation.formatValue(-5.0, unit: "cny/g") == "-¥5.00")
    #expect(MacroPresentation.formatValue(1.92, unit: "%") == "1.92%")
    #expect(MacroPresentation.formatValue(925.4, unit: "tons") == "925.4 吨")
    #expect(MacroPresentation.formatContracts(195_000, signed: true) == "+19.50 万手")
    #expect(MacroPresentation.objectiveStatusLabel(for: .freezing) == "近3年极低分位")
    #expect(MacroPresentation.objectiveStatusLabel(for: .cool) == "拥挤度较低")
    #expect(MacroPresentation.objectiveStatusLabel(for: .neutral) == "热度均衡")
    #expect(MacroPresentation.objectiveStatusLabel(for: .warm) == "关注度偏高")
    #expect(MacroPresentation.objectiveStatusLabel(for: .hot) == "拥挤度偏高")

    #expect(MacroPresentation.normalizedSparkline([]) == [])
    #expect(MacroPresentation.normalizedSparkline([10, 10, 10]) == [0.5, 0.5, 0.5])
    #expect(MacroPresentation.normalizedSparkline([10, 20, 30]) == [0.0, 0.5, 1.0])
}

@Test func sourceLabelLocalizesAllSourcesWithNormalizationAndFallbacks() {
    let expectedSources: [(String, String)] = [
        ("treasury", "美国财政部"),
        ("fred", "美联储经济数据（FRED）"),
        ("yahoo", "雅虎财经"),
        ("spdr", "SPDR 黄金 ETF 官方"),
        ("cftc", "美国商品期货交易委员会（CFTC）"),
        ("bitcoin", "Blockchain.com"),
        ("imf", "国际货币基金组织（IMF）"),
        ("seedcsv", "历史统计归档"),
        ("derived", "公开数据衍生计算")
    ]

    for (raw, expected) in expectedSources {
        #expect(MacroPresentation.sourceLabel(raw) == expected)
        #expect(MacroPresentation.sourceLabel("  \(raw.uppercased()) \n") == expected)
    }

    #expect(MacroPresentation.sourceLabel("") == "—")
    #expect(MacroPresentation.sourceLabel("   \t\n  ") == "—")
    #expect(MacroPresentation.sourceLabel("CustomVendor") == "CustomVendor")
    #expect(MacroPresentation.sourceLabel("  CustomVendor  ") == "CustomVendor")
}

@Test func unitLabelLocalizesAllUnitsWithNormalizationAndFallbacks() {
    let expectedUnits: [(String, String)] = [
        ("trillion_usd", "万亿美元"),
        ("billion_usd", "十亿美元"),
        ("million_usd", "百万美元"),
        ("usd", "美元"),
        ("percent", "百分比（%）"),
        ("%", "百分比（%）"),
        ("index", "指数点"),
        ("tons", "吨"),
        ("contracts", "手（期货合约）"),
        ("ratio", "比值"),
        ("cny/usd", "人民币/美元"),
        ("cny/g", "人民币/克")
    ]

    for (raw, expected) in expectedUnits {
        #expect(MacroPresentation.unitLabel(raw) == expected)
        #expect(MacroPresentation.unitLabel("  \(raw.uppercased()) \n") == expected)
    }

    // 兼容服务端 catalog.go 中的混合大小写原值
    #expect(MacroPresentation.unitLabel("CNY/USD") == "人民币/美元")
    #expect(MacroPresentation.unitLabel("CNY/g") == "人民币/克")

    #expect(MacroPresentation.unitLabel("") == "—")
    #expect(MacroPresentation.unitLabel("   \t\n  ") == "—")
    #expect(MacroPresentation.unitLabel("EUR/USD") == "EUR/USD")
    #expect(MacroPresentation.unitLabel("  EUR/USD  ") == "EUR/USD")
}

@Test func decodesTemperatureGuideHelpWithOfficialAccount() throws {
    let json = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "as_of": "2026-11-21",
        "model_version": "v1",
        "degraded": false,
        "missing_factors": [],
        "score": 32.4,
        "level": "cool",
        "level_label": "偏冷区间",
        "change_1d": -0.8,
        "change_5d": -2.1,
        "volatility_alert": false,
        "volatility_note": "",
        "macro_regime": {
          "score": 71.0,
          "regime": "tailwind",
          "label": "宏观偏暖",
          "summary": "美债与央行购金等长期宏观指标偏强。"
        },
        "action_guide": {
          "signal": "cool_tailwind",
          "title": "偏冷区间 · 宏观偏暖",
          "summary": "五维市场热度处于近3年偏低分位，交易拥挤度较低。",
          "dca_multiplier": 1.2,
          "dca_label": "拥挤度较低",
          "ma200_deviation_pct": -3.12,
          "ma200_note": "低于200日均线3.12%，处于年线下方。",
          "domestic_premium_pct": -0.42,
          "domestic_premium_note": "国内金价较国际折价 -0.42%。",
          "disclaimer": "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
        },
        "dimensions": [],
        "guide_help": {
          "title": "黄金温度计说明",
          "methodology": "综合 5 个维度近 3 年滚动历史分位加权合成（0°~100°），仅客观刻画市场冷热与拥挤程度。",
          "levels": [
            { "range": "0° ~ 20°", "level": "freezing", "label": "极冷区间", "description": "情绪与交易热度处于近 3 年低位" },
            { "range": "20° ~ 40°", "level": "cool", "label": "偏冷区间", "description": "交易拥挤度较低，市场情绪尚未过热" },
            { "range": "40° ~ 60°", "level": "neutral", "label": "中性区间", "description": "多空力量相对均衡，市场热度处于常态" },
            { "range": "60° ~ 80°", "level": "warm", "label": "偏热区间", "description": "资金关注度升温，交投活跃度偏高" },
            { "range": "80° ~ 100°", "level": "hot", "label": "极热区间", "description": "短期偏离与多头拥挤度处于高位" }
          ],
          "official_account_name": "记金宏观笔记",
          "official_account_note": "每日宏观数据复盘与模型方法论笔记同步更新于微信公众号"
        }
      }
    }
    """

    let report = try BackendMacroService.decodeEnvelope(MacroTemperatureReport.self, from: Data(json.utf8))
    let help = try #require(report.guideHelp)
    #expect(help.displayTitle == "黄金温度计说明")
    #expect(help.displayMethodology.contains("5 个维度"))
    #expect(help.displayLevels.count == 5)
    #expect(help.displayLevels[0].level == .freezing)
    #expect(help.displayLevels[0].range == "0° ~ 20°")
    #expect(help.displayLevels[4].level == .hot)
    #expect(help.hasOfficialAccount)
    #expect(help.trimmedOfficialAccountName == "记金宏观笔记")
    #expect(help.trimmedOfficialAccountNote == "每日宏观数据复盘与模型方法论笔记同步更新于微信公众号")
    #expect(report.resolvedGuideHelp == help)
}

@Test func guideHelpPartialOrEmptyFieldsUseObjectiveFallbacks() throws {
    let partialWithAccount = MacroTemperatureGuideHelp(
        title: "   ",
        methodology: "",
        levels: [],
        officialAccountName: "  记金数据笔记  ",
        officialAccountNote: ""
    )
    #expect(partialWithAccount.displayTitle == MacroTemperatureGuideHelp.defaultGuide.title)
    #expect(partialWithAccount.displayMethodology == MacroTemperatureGuideHelp.defaultGuide.methodology)
    #expect(partialWithAccount.displayLevels.count == 5)
    #expect(partialWithAccount.hasOfficialAccount)
    #expect(partialWithAccount.trimmedOfficialAccountName == "记金数据笔记")
    #expect(partialWithAccount.trimmedOfficialAccountNote == MacroTemperatureGuideHelp.defaultOfficialAccountNote)

    let emptyAccount = MacroTemperatureGuideHelp(
        title: "黄金温度计说明",
        methodology: "客观方法论",
        levels: MacroTemperatureGuideHelp.defaultGuide.levels,
        officialAccountName: "   ",
        officialAccountNote: ""
    )
    #expect(!emptyAccount.hasOfficialAccount)
    #expect(emptyAccount.trimmedOfficialAccountNote.isEmpty)
}

@Test func legacyAdvisoryActionGuideFallsBackToObjectiveCopy() throws {
    let forbidden = [
        "操作指南针", "逢低", "加配", "定投", "加仓", "减仓", "止盈", "建仓", "追高", "知识星球", "付费社群", "安全垫", "划算"
    ]

    let cases: [(MacroTemperatureLevel, String, String, String, String)] = [
        (.freezing, "加倍定投", "极冷黄金坑，逢低加配", "建议双倍定投分批建仓。", "近3年极低分位"),
        (.cool, "定投 1.2x", "偏冷蓄势，逢低加配", "市场情绪尚未拥挤，适合按计划分批配置。", "拥挤度较低"),
        (.neutral, "正常定投", "按计划定投", "温度温和，保持正常定投节奏。", "热度均衡"),
        (.warm, "减半定投", "顺风偏热，放慢节奏", "长期顺风但短期偏热，定投减半、不追高。", "关注度偏高"),
        (.hot, "暂停定投", "极度火热，分批止盈", "短期拥挤度极高，建议减仓止盈。", "拥挤度偏高")
    ]

    for (level, legacyLabel, legacyTitle, legacySummary, expectedBadge) in cases {
        let report = MacroTemperatureReport(
            asOf: "2026-11-21",
            modelVersion: "v1",
            degraded: false,
            missingFactors: [],
            score: 50,
            level: level,
            levelLabel: level.defaultLabel,
            change1d: 0.4,
            change5d: -0.6,
            volatilityAlert: true,
            volatilityNote: "黄金波动率处于近3年高位，建议分批控制仓位。",
            macroRegime: MacroRegime(score: 70, regime: .tailwind, label: "宏观偏暖", summary: "长期指标偏强"),
            actionGuide: MacroActionGuide(
                signal: "legacy",
                title: legacyTitle,
                summary: legacySummary,
                dcaMultiplier: 1.2,
                dcaLabel: legacyLabel,
                ma200DeviationPct: 14.35,
                ma200Note: "高于200日均线14.35%，短期安全垫偏薄。",
                domesticPremiumPct: -0.42,
                domesticPremiumNote: "国内折价较划算，适合逢低关注。",
                disclaimer: ""
            ),
            dimensions: []
        )

        let badge = MacroPresentation.objectiveStatusBadge(for: report.actionGuide, level: report.level)
        let title = MacroPresentation.objectiveGuideTitle(for: report)
        let summary = MacroPresentation.objectiveGuideSummary(for: report)
        let ma200Note = MacroPresentation.objectiveMa200Note(for: report.actionGuide)
        let premiumNote = MacroPresentation.objectiveDomesticPremiumNote(for: report.actionGuide)
        let volNote = MacroPresentation.objectiveVolatilityNote(for: report)
        let disclaimer = MacroPresentation.objectiveDisclaimer(for: report.actionGuide)

        #expect(badge == expectedBadge)
        #expect(ma200Note.contains("14.35%"))
        #expect(premiumNote.contains("-0.42%"))
        #expect(!disclaimer.isEmpty)

        for rendered in [badge, title, summary, ma200Note, premiumNote, volNote] {
            for word in forbidden {
                #expect(!rendered.contains(word), "文案「\(rendered)」不应包含违规词「\(word)」")
            }
        }
    }
}

@Test func objectiveBackendCopyPassesThroughAndDefaultsAreCompliant() {
    let report = MacroTemperatureReport(
        asOf: "2026-11-21",
        modelVersion: "v1",
        degraded: false,
        missingFactors: [],
        score: 34.0,
        level: .cool,
        levelLabel: "偏冷区间",
        change1d: -0.5,
        change5d: -1.8,
        volatilityAlert: false,
        volatilityNote: "黄金隐含波动率（GVZ=28.7）处于近 3 年 91% 高位，历史同期短期振幅往往放大",
        macroRegime: MacroRegime(score: 72, regime: .tailwind, label: "宏观偏暖", summary: "长期指标偏强"),
        actionGuide: MacroActionGuide(
            signal: "cool_tailwind",
            title: "偏冷区间 · 宏观偏暖",
            summary: "五维市场热度处于近 3 年偏低分位，同时美债与央行购金等长期宏观指标偏强，整体呈现“宏观偏暖、短线偏冷”特征。",
            dcaMultiplier: 1.2,
            dcaLabel: "拥挤度较低",
            ma200DeviationPct: -3.2,
            ma200Note: "低于 200 日均线 3.20%，处于年线下方",
            domesticPremiumPct: -0.42,
            domesticPremiumNote: "国内金价较国际折价 -0.42%",
            disclaimer: "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
        ),
        dimensions: []
    )

    #expect(MacroPresentation.objectiveStatusBadge(for: report.actionGuide, level: report.level) == "拥挤度较低")
    #expect(MacroPresentation.objectiveGuideTitle(for: report) == "偏冷区间 · 宏观偏暖")
    #expect(MacroPresentation.objectiveGuideSummary(for: report) == report.actionGuide.summary)
    #expect(MacroPresentation.objectiveMa200Note(for: report.actionGuide) == report.actionGuide.ma200Note)
    #expect(MacroPresentation.objectiveDomesticPremiumNote(for: report.actionGuide) == report.actionGuide.domesticPremiumNote)
    #expect(MacroPresentation.objectiveVolatilityNote(for: report) == report.volatilityNote)

    let defaultHelp = MacroTemperatureGuideHelp.defaultGuide
    #expect(!defaultHelp.hasOfficialAccount)
    #expect(defaultHelp.displayLevels.count == 5)
    for level in MacroTemperatureLevel.allCases {
        #expect(!MacroPresentation.containsAdvisoryTerms(level.defaultLabel))
        #expect(!MacroPresentation.containsAdvisoryTerms(MacroPresentation.objectiveStatusLabel(for: level)))
    }
    for regime in MacroRegimeKind.allCases {
        #expect(!MacroPresentation.containsAdvisoryTerms(regime.defaultLabel))
    }
    for item in defaultHelp.displayLevels {
        #expect(!MacroPresentation.containsAdvisoryTerms(item.label))
        #expect(!MacroPresentation.containsAdvisoryTerms(item.description))
    }
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
            signal: "neutral_tailwind",
            title: "中性区间 · 多空相对均衡",
            summary: "五维市场热度处于近3年中位区间，多空力量相对均衡。",
            dcaMultiplier: 1.0,
            dcaLabel: "热度均衡",
            ma200DeviationPct: 8.2,
            ma200Note: "高于200日均线8.20%，处于年线上方",
            domesticPremiumPct: 0.25,
            domesticPremiumNote: "国内金价较国际溢价 +0.25%",
            disclaimer: "数据与温度模型基于公开宏观及市场统计测算，仅反映历史分位与市场热度状态，不构成任何投资建议。"
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

private final class CountingMacroService: MacroServicing, @unchecked Sendable {
    var temperatureCalls = 0
    var historyCalls = 0
    var treasuryCalls = 0
    var catalogCalls = 0
    var cotCalls = 0

    func fetchTemperature() async throws -> MacroTemperatureReport {
        temperatureCalls += 1
        return MacroFixtureData.sampleTemperature
    }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        historyCalls += 1
        let baseDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let points: [MacroTemperatureHistoryPoint] = (0..<757).map { offset in
            let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: baseDate)!
            let score = 45.0 + sin(Double(offset) * 0.05) * 30.0
            let goldPrice = 2200.0 + Double(offset) * 1.5
            return MacroTemperatureHistoryPoint(
                dateString: formatter.string(from: date),
                date: date,
                score: score,
                level: .neutral,
                goldPriceUSD: goldPrice
            )
        }
        return MacroTemperatureHistory(range: range.rawValue, modelVersion: "v1", points: points)
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        treasuryCalls += 1
        return MacroFixtureData.sampleTreasury
    }

    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog {
        catalogCalls += 1
        return MacroFixtureData.sampleCatalog
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        MacroFixtureData.sampleDetail(seriesID: seriesID, range: range)
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        cotCalls += 1
        return MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [])
    }
}

@MainActor @Test func dashboardLoadActiveTabFetchesOnlySelectedTabDependenciesAndDownsamples() async {
    let spy = CountingMacroService()
    let model = MacroDashboardViewModel(service: spy)
    model.selectedTab = .temperature

    await model.loadActiveTab(deferAfterTransition: false)
    #expect(spy.temperatureCalls == 1)
    #expect(spy.historyCalls == 1)
    #expect(spy.treasuryCalls == 0)
    #expect(spy.catalogCalls == 0)
    #expect(spy.cotCalls == 0)
    #expect(model.temperatureHistory?.points.count == 757)
    #expect(model.displayTemperatureHistoryPoints.count <= 180)
    #expect(model.displayTemperatureHistoryPoints.count >= 90)

    // 切换到美债 Tab 才按需拉取美债接口
    model.selectedTab = .treasury
    await model.loadActiveTab(deferAfterTransition: false)
    #expect(spy.treasuryCalls == 1)
    #expect(spy.catalogCalls == 0)
    #expect(spy.cotCalls == 0)

    // 切换到宏观全景 Tab 才按需拉取目录与 COT 接口
    model.selectedTab = .panorama
    await model.loadActiveTab(deferAfterTransition: false)
    #expect(spy.catalogCalls == 1)
    #expect(spy.cotCalls == 1)
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

// MARK: - 取消与 loading 复位回归测试

private actor CancellableMacroService: MacroServicing {
    enum Mode: Sendable {
        case immediateSuccess
        case throwURLErrorCancelledOnceThenSucceed
        case suspendUntilCancelledWithURLError
        case suspendUntilManualResume
    }

    enum Endpoint: Hashable, Sendable {
        case temperature
        case temperatureHistory
        case treasury
        case catalog
        case cot
        case indicatorDetail
    }

    private var mode: Mode
    private var callCounts: [Endpoint: Int] = [:]
    private var suspended: [UUID: (endpoint: Endpoint, continuation: CheckedContinuation<Void, Error>)] = [:]
    private var cancelledIDs: Set<UUID> = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var expectedArrivalCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
    }

    func callCount(for endpoint: Endpoint) -> Int {
        callCounts[endpoint, default: 0]
    }

    func waitUntilSuspendedCount(atLeast count: Int) async {
        if suspended.count >= count { return }
        expectedArrivalCount = count
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func resumeAllSuspendedSuccess() {
        let items = suspended
        suspended.removeAll()
        for (_, item) in items {
            item.continuation.resume()
        }
    }

    private func registerSuspension(id: UUID, endpoint: Endpoint, continuation: CheckedContinuation<Void, Error>) {
        if cancelledIDs.remove(id) != nil {
            continuation.resume(throwing: URLError(.cancelled))
            return
        }
        suspended[id] = (endpoint, continuation)
        if suspended.count >= expectedArrivalCount, !arrivalWaiters.isEmpty {
            let waiters = arrivalWaiters
            arrivalWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    private func cancelSuspension(id: UUID) {
        if let item = suspended.removeValue(forKey: id) {
            item.continuation.resume(throwing: URLError(.cancelled))
        } else {
            cancelledIDs.insert(id)
        }
    }

    private func gate(_ endpoint: Endpoint) async throws {
        callCounts[endpoint, default: 0] += 1
        let attempt = callCounts[endpoint, default: 0]
        switch mode {
        case .immediateSuccess:
            return
        case .throwURLErrorCancelledOnceThenSucceed:
            if attempt == 1 {
                throw URLError(.cancelled)
            }
            return
        case .suspendUntilCancelledWithURLError:
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    registerSuspension(id: id, endpoint: endpoint, continuation: continuation)
                }
            } onCancel: {
                Task { await self.cancelSuspension(id: id) }
            }
        case .suspendUntilManualResume:
            let id = UUID()
            try await withCheckedThrowingContinuation { continuation in
                registerSuspension(id: id, endpoint: endpoint, continuation: continuation)
            }
        }
    }

    func fetchTemperature() async throws -> MacroTemperatureReport {
        try await gate(.temperature)
        return MacroFixtureData.sampleTemperature
    }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        try await gate(.temperatureHistory)
        return MacroFixtureData.sampleHistory(range: range)
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        try await gate(.treasury)
        return MacroFixtureData.sampleTreasury
    }

    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog {
        try await gate(.catalog)
        return MacroFixtureData.sampleCatalog
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        try await gate(.indicatorDetail)
        return MacroFixtureData.sampleDetail(seriesID: seriesID, range: range)
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        try await gate(.cot)
        return MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [])
    }
}

@Test func isCancellationErrorClassifiesCancellationProperly() {
    #expect(MacroDashboardViewModel.isCancellationError(URLError(.cancelled)))
    #expect(MacroDashboardViewModel.isCancellationError(CancellationError()))
    #expect(!MacroDashboardViewModel.isCancellationError(URLError(.timedOut)))
    #expect(!MacroDashboardViewModel.isCancellationError(URLError(.notConnectedToInternet)))
    #expect(!MacroDashboardViewModel.isCancellationError(BackendMacroService.ServiceError.httpStatus(503)))
}

@MainActor @Test func loadSummaryResetsLoadingAndRecoversAfterURLErrorCancelled() async {
    let service = CancellableMacroService(mode: .throwURLErrorCancelledOnceThenSucceed)
    let model = MacroDashboardViewModel(service: service)

    // 首次请求被 URLSession 以 URLError(.cancelled) 取消：不得卡死 loading，也不得污染错误提示。
    await model.loadSummary(force: false)
    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isSummaryLoading)
    #expect(model.temperature == nil)
    #expect(model.treasury == nil)
    #expect(model.temperatureError == nil)
    #expect(model.treasuryError == nil)
    #expect(await service.callCount(for: .temperature) == 1)
    #expect(await service.callCount(for: .treasury) == 1)

    // 再次以 force: false 调用 loadSummary()，应能顺利发起请求并加载完整数据。
    await model.loadSummary(force: false)
    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isSummaryLoading)
    #expect(model.temperature?.score == MacroFixtureData.sampleTemperature.score)
    #expect(model.treasury?.summary.totalDebtTrillionUSD == MacroFixtureData.sampleTreasury.summary.totalDebtTrillionUSD)
    #expect(model.temperatureError == nil)
    #expect(model.treasuryError == nil)
    #expect(await service.callCount(for: .temperature) == 2)
    #expect(await service.callCount(for: .treasury) == 2)
}

@MainActor @Test func loadSummaryResetsLoadingWhenTaskCancelledInFlightAndRecovers() async {
    let service = CancellableMacroService(mode: .suspendUntilCancelledWithURLError)
    let model = MacroDashboardViewModel(service: service)

    let summaryTask = Task { await model.loadSummary(force: false) }
    await service.waitUntilSuspendedCount(atLeast: 2)
    #expect(model.isLoadingTemperature)
    #expect(model.isLoadingTreasury)
    #expect(model.isSummaryLoading)

    // 模拟冷启动 scenePhase 抖动导致 .task 取消，底层 URLSession 抛出 URLError(.cancelled)。
    summaryTask.cancel()
    await summaryTask.value

    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isSummaryLoading)
    #expect(model.temperature == nil)
    #expect(model.treasury == nil)
    #expect(model.temperatureError == nil)
    #expect(model.treasuryError == nil)

    await service.setMode(.immediateSuccess)
    await model.loadSummary(force: false)
    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingTreasury)
    #expect(model.temperature?.score == MacroFixtureData.sampleTemperature.score)
    #expect(model.treasury?.summary.totalDebtTrillionUSD == MacroFixtureData.sampleTreasury.summary.totalDebtTrillionUSD)
    #expect(model.temperatureError == nil)
    #expect(model.treasuryError == nil)
}

@MainActor @Test func loadSummaryResetsLoadingWhenCancelledBeforeResponseApplies() async {
    let service = CancellableMacroService(mode: .suspendUntilManualResume)
    let model = MacroDashboardViewModel(service: service)

    let summaryTask = Task { await model.loadSummary(force: false) }
    await service.waitUntilSuspendedCount(atLeast: 2)

    // 模拟任务取消但底层请求仍正常返回结果（命中 do 块 guard !Task.isCancelled 提前 return 分支）。
    summaryTask.cancel()
    await service.resumeAllSuspendedSuccess()
    await summaryTask.value

    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isSummaryLoading)
    #expect(model.temperature == nil)
    #expect(model.treasury == nil)
    #expect(model.temperatureError == nil)
    #expect(model.treasuryError == nil)

    await service.setMode(.immediateSuccess)
    await model.loadSummary(force: false)
    #expect(model.temperature?.score == MacroFixtureData.sampleTemperature.score)
    #expect(model.treasury?.summary.totalDebtTrillionUSD == MacroFixtureData.sampleTreasury.summary.totalDebtTrillionUSD)
}

@MainActor @Test func loadDashboardResetsAllLoadingFlagsAfterTaskCancellationAndRecovers() async {
    let service = CancellableMacroService(mode: .suspendUntilCancelledWithURLError)
    let model = MacroDashboardViewModel(service: service)

    let dashboardTask = Task { await model.loadDashboard(force: false) }
    await service.waitUntilSuspendedCount(atLeast: 5)
    #expect(model.isLoadingTemperature)
    #expect(model.isLoadingHistory)
    #expect(model.isLoadingTreasury)
    #expect(model.isLoadingCatalog)
    #expect(model.isLoadingCot)

    dashboardTask.cancel()
    await dashboardTask.value

    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingHistory)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isLoadingCatalog)
    #expect(!model.isLoadingCot)
    #expect(!model.isSummaryLoading)
    #expect(!model.isRefreshingCurrentTab)
    #expect(model.temperatureError == nil)
    #expect(model.historyError == nil)
    #expect(model.treasuryError == nil)
    #expect(model.catalogError == nil)
    #expect(model.cotError == nil)

    await service.setMode(.immediateSuccess)
    await model.loadDashboard(force: false)
    #expect(model.temperature?.score == MacroFixtureData.sampleTemperature.score)
    #expect(model.temperatureHistory?.points.count == 1)
    #expect(model.treasury?.summary.totalDebtTrillionUSD == MacroFixtureData.sampleTreasury.summary.totalDebtTrillionUSD)
    #expect(model.catalog?.sections.count == 2)
    #expect(model.cot?.seriesID == "GOLD_COT")
    #expect(!model.isLoadingTemperature)
    #expect(!model.isLoadingHistory)
    #expect(!model.isLoadingTreasury)
    #expect(!model.isLoadingCatalog)
    #expect(!model.isLoadingCot)
}

@MainActor @Test func indicatorDetailResetsLoadingAndRecoversAfterURLErrorAndTaskCancel() async {
    let urlCancelService = CancellableMacroService(mode: .throwURLErrorCancelledOnceThenSucceed)
    let firstModel = MacroIndicatorDetailViewModel(seriesID: "DFII10", service: urlCancelService)

    await firstModel.load()
    #expect(!firstModel.isLoading)
    #expect(firstModel.errorMessage == nil)
    #expect(firstModel.detail == nil)

    await firstModel.load()
    #expect(!firstModel.isLoading)
    #expect(firstModel.errorMessage == nil)
    #expect(firstModel.detail?.seriesID == "DFII10")

    let taskCancelService = CancellableMacroService(mode: .suspendUntilCancelledWithURLError)
    let secondModel = MacroIndicatorDetailViewModel(seriesID: "DFII10", service: taskCancelService)

    let loadTask = Task { await secondModel.load() }
    await taskCancelService.waitUntilSuspendedCount(atLeast: 1)
    #expect(secondModel.isLoading)

    loadTask.cancel()
    await loadTask.value

    #expect(!secondModel.isLoading)
    #expect(secondModel.errorMessage == nil)
    #expect(secondModel.detail == nil)

    await taskCancelService.setMode(.immediateSuccess)
    await secondModel.load()
    #expect(!secondModel.isLoading)
    #expect(secondModel.errorMessage == nil)
    #expect(secondModel.detail?.seriesID == "DFII10")
}

@MainActor @Test func renderComplianceCardAndGuideSheetForVisualReview() async throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-compliance-ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let helpWithOfficial = MacroTemperatureGuideHelp(
        title: "黄金温度计说明",
        methodology: MacroTemperatureGuideHelp.defaultGuide.methodology,
        levels: MacroTemperatureGuideHelp.defaultGuide.levels,
        officialAccountName: "记金宏观笔记",
        officialAccountNote: MacroTemperatureGuideHelp.defaultOfficialAccountNote
    )

    let report = MacroTemperatureReport(
        asOf: "2026-11-21",
        modelVersion: "v1",
        degraded: false,
        missingFactors: [],
        score: 32.4,
        level: .cool,
        levelLabel: "偏冷区间",
        change1d: -1.1,
        change5d: -3.4,
        volatilityAlert: false,
        volatilityNote: "",
        macroRegime: MacroRegime(
            score: 74.0,
            regime: .tailwind,
            label: "宏观偏暖",
            summary: "美债高企叠加央行购金，中长期宏观指标偏强。"
        ),
        actionGuide: MacroActionGuide(
            signal: "cool_tailwind",
            title: "偏冷区间 · 宏观偏暖",
            summary: "五维市场热度处于近 3 年偏低分位，同时美债与央行购金等长期宏观指标偏强，整体呈现“宏观偏暖、短线偏冷”特征。",
            dcaMultiplier: 1.2,
            dcaLabel: "拥挤度较低",
            ma200DeviationPct: -3.12,
            ma200Note: "低于 200 日均线 3.12%，处于年线下方",
            domesticPremiumPct: -0.42,
            domesticPremiumNote: "国内金价较国际折价 -0.42%",
            disclaimer: MacroPresentation.defaultDisclaimer
        ),
        dimensions: [
            MacroTemperatureDimension(
                key: "trend_momentum",
                name: "趋势与动量",
                weight: 0.30,
                score: 30.5,
                available: true,
                status: "cool",
                summary: "短期价格位于 200 日均线下方，动量温和。"
            )
        ],
        guideHelp: helpWithOfficial
    )

    let legacyReport = MacroTemperatureReport(
        asOf: "2026-11-21",
        modelVersion: "v1",
        degraded: false,
        missingFactors: [],
        score: 71.6,
        level: .warm,
        levelLabel: "偏热区间",
        change1d: 1.8,
        change5d: 4.2,
        volatilityAlert: true,
        volatilityNote: "黄金波动率处于近3年高位，建议分批控制仓位。",
        macroRegime: MacroRegime(score: 72, regime: .tailwind, label: "宏观偏暖", summary: "长期指标偏强"),
        actionGuide: MacroActionGuide(
            signal: "reduce_pace",
            title: "顺风偏热，放慢节奏",
            summary: "长期顺风但短期偏热，定投减半、不追高。",
            dcaMultiplier: 0.5,
            dcaLabel: "减半定投",
            ma200DeviationPct: 14.35,
            ma200Note: "高于200日均线14.35%，短期安全垫偏薄。",
            domesticPremiumPct: 0.42,
            domesticPremiumNote: "国内溢价不划算。",
            disclaimer: ""
        ),
        dimensions: []
    )

    let homeCardsPreview = ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("首页温度卡（新版服务端客观文案 + 问号入口）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textSecondary)

            GoldTemperatureCard(
                temperature: report,
                treasury: MacroFixtureData.sampleTreasury.summary,
                isLoading: false,
                errorMessage: nil,
                onRetry: {},
                onOpenDashboard: {}
            )

            Text("首页温度卡（旧版服务端含定投字段 → 前端自动客观化兜底）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textSecondary)
                .padding(.top, 4)

            GoldTemperatureCard(
                temperature: legacyReport,
                treasury: MacroFixtureData.sampleTreasury.summary,
                isLoading: false,
                errorMessage: nil,
                onRetry: {},
                onOpenDashboard: {}
            )
        }
        .padding(16)
    }
    .background(GoldTheme.background)

    let sheetWithOfficialPreview = MacroTemperatureGuideSheet(
        help: helpWithOfficial,
        disclaimer: report.actionGuide.disclaimer,
        currentLevel: report.level
    )

    let sheetWithoutOfficialPreview = MacroTemperatureGuideSheet(
        help: .defaultGuide,
        disclaimer: report.actionGuide.disclaimer,
        currentLevel: report.level
    )

    let fixtures: [(String, AnyView)] = [
        ("compliance-home-cards", AnyView(homeCardsPreview)),
        ("compliance-guide-sheet-official", AnyView(sheetWithOfficialPreview)),
        ("compliance-guide-sheet-default", AnyView(sheetWithoutOfficialPreview))
    ]

    for (name, rootView) in fixtures {
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(
            rootView: rootView
                .preferredColorScheme(.dark)
                .tint(GoldTheme.gold)
        )
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("COMPLIANCE_RENDER_ARTIFACT: \(path.path)")
        window.isHidden = true
    }
    previous?.makeKey()
}

// MARK: - 美债财政压力表 & 宏观全景温度计套件

@Suite("MacroSupplementaryGauges Tests")
struct MacroSupplementaryGaugesTests {
    private static let extraForbiddenWords: [String] = [
        "偏暖", "操作指南针", "逢低", "加配", "定投", "加仓", "减仓", "止盈",
        "建仓", "追高", "抄底", "知识星球", "付费社群", "建议", "适合", "划算",
        "黄金坑", "安全垫", "分批", "仓位", "买入", "卖出", "放慢节奏", "防守",
        "试探", "便宜", "贵", "买点", "卖点", "机会", "配置", "入场", "离场"
    ]

    private static func makeSummary(
        debtToGDP: Double? = 122.8,
        interestToRevenue: Double? = 18.4,
        totalDebt: Double? = 36.21,
        fiscalStress: Double? = 76.5
    ) -> MacroTreasurySummary {
        MacroTreasurySummary(
            totalDebtTrillionUSD: totalDebt,
            debtChangeYoYTrillion: 2.15,
            debtToGDPPct: debtToGDP,
            interestToRevenuePct: interestToRevenue,
            fiscalStressScore: fiscalStress,
            yield10yNominalPct: 4.32,
            yield2yNominalPct: 4.18,
            spread10y2yPct: 0.14,
            yield10yRealPct: 1.92,
            breakeven10yPct: 2.40,
            tltPrice: 91.25,
            goldImpactNote: ""
        )
    }

    private static func makeIndicator(
        id: String,
        name: String = "测试指标",
        section: String = "treasury_fiscal",
        unit: String = "%",
        relation: String = "positive",
        latestValue: Double? = 50.0,
        percentile3y: Double? = 60.0
    ) -> MacroIndicatorSummary {
        MacroIndicatorSummary(
            seriesID: id,
            nameZh: name,
            section: section,
            unit: unit,
            frequency: "daily",
            source: "fred",
            goldRelation: relation,
            plainNote: "",
            latestDate: "2026-11-21",
            latestValue: latestValue,
            change5d: nil,
            change20d: nil,
            change3m: nil,
            changeYoY: nil,
            percentile3y: percentile3y,
            sparkline: []
        )
    }

    @Test func treasuryPressureFiveTierBoundariesAndClamping() {
        let cases: [(Double, MacroTreasuryPressureLevel, String)] = [
            (-10.0, .low, "压力偏低"),
            (0.0, .low, "压力偏低"),
            (24.99, .low, "压力偏低"),
            (25.0, .moderate, "温和区间"),
            (44.99, .moderate, "温和区间"),
            (45.0, .elevated, "压力偏高"),
            (64.99, .elevated, "压力偏高"),
            (65.0, .high, "高压区间"),
            (79.99, .high, "高压区间"),
            (80.0, .extreme, "极高压力"),
            (100.0, .extreme, "极高压力"),
            (130.0, .extreme, "极高压力")
        ]

        for (score, expectedLevel, expectedLabel) in cases {
            let level = MacroTreasuryPressureLevel.from(score: score)
            #expect(level == expectedLevel)
            #expect(level.label == expectedLabel)
        }

        #expect(MacroTreasuryPressureLevel.from(score: .nan) == .elevated)
        #expect(MacroTreasuryPressureLevel.from(score: .infinity) == .elevated)
    }

    @Test func treasuryPressureExtractsDriversAndHandlesSummaryFallbackAndUnavailable() {
        // 1. 优先使用 summary.fiscalStressScore 与三项核心驱动指标
        let primary = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: 122.8, interestToRevenue: 18.4, totalDebt: 36.21, fiscalStress: 78.5),
            cards: [Self.makeIndicator(id: "FISCAL_STRESS", unit: "index", latestValue: 50.0)]
        )
        #expect(primary.hasScore)
        #expect(primary.score == 78.5)
        #expect(primary.scoreSource == .summary)
        #expect(primary.scoreText == "78.5")
        #expect(primary.level == .high)
        #expect(primary.levelLabel == "高压区间")
        #expect(primary.drivers.count == 3)
        #expect(primary.drivers[0].title == "债务 / GDP")
        #expect(primary.drivers[0].valueText == "122.80%")
        #expect(primary.drivers[1].title == "付息 / 财政收入")
        #expect(primary.drivers[1].valueText == "18.40%")
        #expect(primary.drivers[2].title == "国债总规模")
        #expect(primary.drivers[2].valueText == "$36.21 万亿")

        // 2. fiscalStressScore 缺失时回退到 cards 中的 FISCAL_STRESS，不编造数据
        let cardFallback = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: nil, interestToRevenue: nil, totalDebt: nil, fiscalStress: nil),
            cards: [
                Self.makeIndicator(id: "fiscal_stress", unit: "index", latestValue: 84.2),
                Self.makeIndicator(id: "GFDEGDQ188S", unit: "%", latestValue: 121.0),
                Self.makeIndicator(id: "INTEREST_RATIO", unit: "%", latestValue: 17.5),
                Self.makeIndicator(id: "US_DEBT_DAILY", unit: "trillion_usd", latestValue: 35.9)
            ]
        )
        #expect(cardFallback.hasScore)
        #expect(cardFallback.score == 84.2)
        #expect(cardFallback.scoreSource == .cardFallback)
        #expect(cardFallback.level == .extreme)
        #expect(cardFallback.levelLabel == "极高压力")
        #expect(cardFallback.drivers[0].valueText == "121.00%")
        #expect(cardFallback.drivers[1].valueText == "17.50%")
        #expect(cardFallback.drivers[2].valueText == "$35.90 万亿")

        // 3. 完全缺失或非有限值时优雅降级为待同步占位，不编造数值
        let unavailable = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: nil, interestToRevenue: nil, totalDebt: nil, fiscalStress: .nan),
            cards: []
        )
        #expect(!unavailable.hasScore)
        #expect(unavailable.score == nil)
        #expect(unavailable.level == nil)
        #expect(unavailable.scoreSource == .unavailable)
        #expect(unavailable.scoreText == "—")
        #expect(unavailable.levelLabel == "待同步")
        #expect(unavailable.drivers.allSatisfy { !$0.hasValue && $0.valueText == "—" })

        let sendableCheck: any Sendable = primary
        #expect(sendableCheck is MacroTreasuryPressureModel)
    }

    @Test func panoramaThermometerPrefersMacroRegimeAndFallsBackToCatalogByGoldRelation() {
        let sixSectionsCatalog = MacroIndicatorsCatalog(sections: [
            // 1. positive 90 + negative 10 (-> 90) + neutral 30 (跳过) => 90° (极热)
            MacroIndicatorSection(
                id: "treasury_fiscal",
                nameZh: "美债与财政信用",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "US_DEBT_DAILY", section: "treasury_fiscal", relation: "positive", percentile3y: 90.0),
                    Self.makeIndicator(id: "USD_RESERVE_SHARE", section: "treasury_fiscal", relation: "negative", percentile3y: 10.0),
                    Self.makeIndicator(id: "FYFR", section: "treasury_fiscal", relation: "neutral", percentile3y: 30.0)
                ]
            ),
            // 2. negative 30 (-> 70) + positive 60 => 65° (偏热)
            MacroIndicatorSection(
                id: "opportunity_cost",
                nameZh: "利率与机会成本",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "DFII10", section: "opportunity_cost", relation: "negative", percentile3y: 30.0),
                    Self.makeIndicator(id: "T10YIE", section: "opportunity_cost", relation: "positive", percentile3y: 60.0),
                    Self.makeIndicator(id: "DGS2", section: "opportunity_cost", relation: "negative", percentile3y: nil)
                ]
            ),
            // 3. 全为 neutral => 取原始均值 (45 + 55) / 2 = 50° (中性)
            MacroIndicatorSection(
                id: "dollar_liquidity",
                nameZh: "美元与流动性",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "DEXCHUS", section: "dollar_liquidity", relation: "neutral", percentile3y: 45.0),
                    Self.makeIndicator(id: "NFCI", section: "dollar_liquidity", relation: "mixed", percentile3y: 55.0)
                ]
            ),
            // 4. positive 30 => 30° (偏冷)
            MacroIndicatorSection(
                id: "inflation_growth",
                nameZh: "通胀与增长",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "PCEPILFE", section: "inflation_growth", relation: "positive", percentile3y: 30.0)
                ]
            ),
            // 5. negative 88 (-> 12) => 12° (极冷)
            MacroIndicatorSection(
                id: "official_market",
                nameZh: "贵金属与跨资产",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "GOLD_SILVER_RATIO", section: "official_market", relation: "negative", percentile3y: 88.0)
                ]
            ),
            // 6. 全部无 percentile3y => nil (待同步)
            MacroIndicatorSection(
                id: "risk_temperature",
                nameZh: "资金情绪与波动",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "GVZCLS", section: "risk_temperature", relation: "positive", percentile3y: nil)
                ]
            )
        ])

        // 场景 A：temperature 可用时，综合读数严格同源 macroRegime.score (68.0)
        let withTemp = MacroPanoramaThermometerModel.make(
            temperature: MacroFixtureData.sampleTemperature,
            catalog: sixSectionsCatalog
        )
        #expect(withTemp.scoreSource == .macroRegime)
        #expect(withTemp.score == 68.0)
        #expect(withTemp.level == .warm)
        #expect(withTemp.levelLabel == "偏热区间")
        #expect(withTemp.pillars.count == 6)

        #expect(withTemp.pillars[0].score == 90.0)
        #expect(withTemp.pillars[0].shortStatusLabel == "极热")
        #expect(withTemp.pillars[0].validIndicatorCount == 2)
        #expect(withTemp.pillars[0].totalIndicatorCount == 3)

        #expect(withTemp.pillars[1].score == 65.0)
        #expect(withTemp.pillars[1].shortStatusLabel == "偏热")
        #expect(withTemp.pillars[1].validIndicatorCount == 2)

        #expect(withTemp.pillars[2].score == 50.0)
        #expect(withTemp.pillars[2].shortStatusLabel == "中性")
        #expect(withTemp.pillars[2].validIndicatorCount == 2)

        #expect(withTemp.pillars[3].score == 30.0)
        #expect(withTemp.pillars[3].shortStatusLabel == "偏冷")

        #expect(withTemp.pillars[4].score == 12.0)
        #expect(withTemp.pillars[4].shortStatusLabel == "极冷")

        #expect(withTemp.pillars[5].score == nil)
        #expect(withTemp.pillars[5].shortStatusLabel == "待同步")
        #expect(withTemp.pillars[5].validIndicatorCount == 0)

        #expect(withTemp.hotPillarCount == 2)
        #expect(withTemp.neutralPillarCount == 1)
        #expect(withTemp.coldPillarCount == 2)

        // 场景 B：temperature == nil 时，按全部方向性指标折算均值无缝兜底：
        // directional = [90, 90, 70, 60, 30, 12] => sum = 352 / 6 = 58.666...
        let fallback = MacroPanoramaThermometerModel.make(temperature: nil, catalog: sixSectionsCatalog)
        #expect(fallback.scoreSource == .catalogFallback)
        let fallbackScore = fallback.score ?? -1
        #expect(abs(fallbackScore - (352.0 / 6.0)) < 1e-9)
        #expect(fallback.level == .neutral)

        // 场景 C：冷启动 temperature（asOf == ""）同样触发 catalog 兜底
        let coldStart = MacroTemperatureReport(
            asOf: "",
            modelVersion: "v1",
            degraded: true,
            missingFactors: ["trend_momentum"],
            score: 50,
            level: .neutral,
            levelLabel: "中性区间",
            change1d: nil,
            change5d: nil,
            volatilityAlert: false,
            volatilityNote: "",
            macroRegime: MacroRegime(score: 50, regime: .neutral, label: "", summary: ""),
            actionGuide: MacroFixtureData.sampleTemperature.actionGuide,
            dimensions: []
        )
        let coldFallback = MacroPanoramaThermometerModel.make(temperature: coldStart, catalog: sixSectionsCatalog)
        #expect(coldFallback.scoreSource == .catalogFallback)

        // 场景 D：全部仅含 neutral 指标时，总分取 neutral 原始均值
        let neutralOnly = MacroIndicatorsCatalog(sections: [
            MacroIndicatorSection(
                id: "only_neutral",
                nameZh: "纯中性测试",
                description: "",
                indicators: [
                    Self.makeIndicator(id: "N1", relation: "neutral", percentile3y: 40.0),
                    Self.makeIndicator(id: "N2", relation: "neutral", percentile3y: 80.0)
                ]
            )
        ])
        let neutralModel = MacroPanoramaThermometerModel.make(temperature: nil, catalog: neutralOnly)
        #expect(neutralModel.scoreSource == .catalogFallback)
        #expect(neutralModel.score == 60.0)

        // 场景 E：两者皆空时优雅降级
        let emptyModel = MacroPanoramaThermometerModel.make(temperature: nil, catalog: nil)
        #expect(!emptyModel.hasScore)
        #expect(!emptyModel.hasAnyData)
        #expect(emptyModel.scoreSource == .unavailable)
    }

    @Test func pressureGaugeGeometryMatchesInsetCircleAndIndicatorAnglesStrictly() {
        let gDefault = MacroTreasuryPressureGaugeGeometry(score: 76.5)
        #expect(gDefault.strokeInset == gDefault.lineWidth / 2)
        #expect(gDefault.trackRadius == (gDefault.diameter - gDefault.lineWidth) / 2)
        #expect(gDefault.outerStrokeRadius == gDefault.diameter / 2)
        #expect(gDefault.center == CGPoint(x: gDefault.diameter / 2, y: gDefault.diameter / 2))

        // 验证 Circle().inset(by: strokeInset) 路径半径与圆心严格吻合，且外描边不溢出边界框
        let rect = CGRect(x: 0, y: 0, width: gDefault.diameter, height: gDefault.diameter)
        let pathRect = Circle().inset(by: gDefault.strokeInset).path(in: rect).boundingRect
        #expect(abs(pathRect.midX - gDefault.center.x) < 1e-6)
        #expect(abs(pathRect.midY - gDefault.center.y) < 1e-6)
        #expect(abs(pathRect.width / 2 - gDefault.trackRadius) < 1e-6)
        #expect(abs(pathRect.height / 2 - gDefault.trackRadius) < 1e-6)

        let strokedOuterRect = pathRect.insetBy(dx: -gDefault.lineWidth / 2, dy: -gDefault.lineWidth / 2)
        #expect(abs(strokedOuterRect.minX - 0) < 1e-6)
        #expect(abs(strokedOuterRect.minY - 0) < 1e-6)
        #expect(abs(strokedOuterRect.maxX - gDefault.diameter) < 1e-6)
        #expect(abs(strokedOuterRect.maxY - gDefault.diameter) < 1e-6)

        // 起止角度对称（165° 与 375°），50 分严格在正上方 270°
        #expect(abs(MacroTreasuryPressureGaugeGeometry.startAngleDegrees - 165.0) < 1e-12)
        #expect(abs(MacroTreasuryPressureGaugeGeometry.endAngleDegrees - 375.0) < 1e-12)
        #expect(abs((gDefault.startPoint.x - gDefault.center.x) + (gDefault.endPoint.x - gDefault.center.x)) < 1e-9)
        #expect(abs(gDefault.startPoint.y - gDefault.endPoint.y) < 1e-9)

        let mid = MacroTreasuryPressureGaugeGeometry(score: 50.0)
        #expect(abs(mid.indicatorAngleDegrees - 270.0) < 1e-9)
        #expect(abs(mid.indicatorCenter.x - mid.center.x) < 1e-9)
        #expect(abs(mid.indicatorCenter.y - (mid.center.y - mid.trackRadius)) < 1e-9)

        // 全分值扫描：指示点到圆心距离 == trackRadius，且彩色弧终点与指示点严格重合
        let testScores: [Double?] = [nil, -15.0, 0.0, 0.05, 25.0, 45.0, 50.0, 65.0, 80.0, 100.0, 140.0, .nan, .infinity]
        for raw in testScores {
            let g = MacroTreasuryPressureGaugeGeometry(score: raw)
            let dx = Double(g.indicatorCenter.x - g.center.x)
            let dy = Double(g.indicatorCenter.y - g.center.y)
            let distance = hypot(dx, dy)
            #expect(abs(distance - Double(g.trackRadius)) < 1e-9)
            #expect(abs(g.activeArcEndAngleDegrees - g.indicatorAngleDegrees) < 1e-12)
            #expect(abs(g.activeArcEndPoint.x - g.indicatorCenter.x) < 1e-12)
            #expect(abs(g.activeArcEndPoint.y - g.indicatorCenter.y) < 1e-12)
            #expect(g.activeTrimEnd >= MacroTreasuryPressureGaugeGeometry.minimumTrim - 1e-12)
            #expect(g.activeTrimEnd <= MacroTreasuryPressureGaugeGeometry.arcSpan + 1e-12)
        }

        let sendableCheck: any Sendable = gDefault
        #expect(sendableCheck is MacroTreasuryPressureGaugeGeometry)
    }

    @Test func allSupplementaryGaugeCopyIsStrictlyFreeOfAdvisoryTerms() {
        var allTexts: [String] = [
            MacroTreasuryPressureGuideContent.title,
            MacroTreasuryPressureGuideContent.badgeText,
            MacroTreasuryPressureGuideContent.methodology,
            MacroTreasuryPressureGuideContent.goldCreditRelationTitle,
            MacroTreasuryPressureGuideContent.goldCreditRelationNote,
            MacroPanoramaThermometerGuideContent.title,
            MacroPanoramaThermometerGuideContent.badgeText,
            MacroPanoramaThermometerGuideContent.methodology,
            MacroPanoramaThermometerGuideContent.pillarRuleTitle,
            MacroPanoramaThermometerGuideContent.pillarRuleNote,
            MacroTreasuryPressureModel.objectivePlainNote(for: nil)
        ]

        for level in MacroTreasuryPressureLevel.allCases {
            allTexts.append(level.label)
            allTexts.append(level.rangeText)
            allTexts.append(level.guideDescription)
            allTexts.append(MacroTreasuryPressureModel.objectivePlainNote(for: level))
        }

        for level in MacroTemperatureLevel.allCases {
            allTexts.append(MacroPanoramaThermometerGuideContent.levelDescription(for: level))
        }

        // 覆盖全景温度计全部总结分支（混合分化、全偏热、偏热+中性、全偏冷、偏冷+中性、全中性、仅有总分、完全空态）
        let summaryCases: [(MacroTemperatureReport?, MacroIndicatorsCatalog?)] = [
            (nil, nil),
            (MacroFixtureData.sampleTemperature, nil),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 85)]),
                MacroIndicatorSection(id: "b", nameZh: "板块B", description: "", indicators: [Self.makeIndicator(id: "B", relation: "positive", percentile3y: 15)])
            ])),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 75)]),
                MacroIndicatorSection(id: "b", nameZh: "板块B", description: "", indicators: [Self.makeIndicator(id: "B", relation: "positive", percentile3y: 50)])
            ])),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 85)])
            ])),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 25)]),
                MacroIndicatorSection(id: "b", nameZh: "板块B", description: "", indicators: [Self.makeIndicator(id: "B", relation: "positive", percentile3y: 50)])
            ])),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 18)])
            ])),
            (nil, MacroIndicatorsCatalog(sections: [
                MacroIndicatorSection(id: "a", nameZh: "板块A", description: "", indicators: [Self.makeIndicator(id: "A", relation: "positive", percentile3y: 50)])
            ]))
        ]

        for (temp, cat) in summaryCases {
            let model = MacroPanoramaThermometerModel.make(temperature: temp, catalog: cat)
            allTexts.append(model.levelLabel)
            allTexts.append(model.sourceBadgeText)
            allTexts.append(model.summaryText)
            for pillar in model.pillars {
                allTexts.append(pillar.shortStatusLabel)
            }
        }

        for text in allTexts {
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!MacroPresentation.containsAdvisoryTerms(text), "文案「\(text)」包含投顾关键词")
            for word in Self.extraForbiddenWords {
                #expect(!text.contains(word), "文案「\(text)」包含禁用词「\(word)」")
            }
        }
    }

    @MainActor @Test func dashboardToggleSectionAndEnsurePanoramaDependencies() async {
        let model = MacroDashboardViewModel(service: MockMacroService())
        await model.ensurePanoramaDependenciesLoaded()
        #expect(model.temperature?.macroRegime.score == 68)
        #expect(model.catalog?.sections.count == 2)
        #expect(model.panoramaThermometerModel.scoreSource == .macroRegime)
        #expect(model.panoramaThermometerModel.score == 68)

        model.toggleSectionSelection("treasury_fiscal")
        #expect(model.selectedSectionID == "treasury_fiscal")
        #expect(model.filteredSections.map(\.id) == ["treasury_fiscal"])

        // 再次点击同一板块取消筛选
        model.toggleSectionSelection("treasury_fiscal")
        #expect(model.selectedSectionID == nil)
        #expect(model.filteredSections.count == 2)
    }

    @MainActor @Test func renderSupplementaryGaugesAndGuideSheetsForVisualReview() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-supplementary-gauges-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pressureHigh = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: 122.8, interestToRevenue: 18.4, totalDebt: 36.21, fiscalStress: 78.5)
        )
        let pressureLow = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: 62.5, interestToRevenue: 7.2, totalDebt: 18.40, fiscalStress: 19.5)
        )
        let pressureUnavailable = MacroTreasuryPressureModel.make(
            summary: Self.makeSummary(debtToGDP: nil, interestToRevenue: nil, totalDebt: 36.21, fiscalStress: nil)
        )

        let sixCatalog = MacroIndicatorsCatalog(sections: [
            MacroIndicatorSection(id: "treasury_fiscal", nameZh: "美债与财政信用", description: "", indicators: [Self.makeIndicator(id: "US_DEBT_DAILY", relation: "positive", percentile3y: 92)]),
            MacroIndicatorSection(id: "opportunity_cost", nameZh: "利率与机会成本", description: "", indicators: [Self.makeIndicator(id: "DFII10", relation: "negative", percentile3y: 35)]),
            MacroIndicatorSection(id: "dollar_liquidity", nameZh: "美元与流动性", description: "", indicators: [Self.makeIndicator(id: "DTWEXBGS", relation: "negative", percentile3y: 48)]),
            MacroIndicatorSection(id: "inflation_growth", nameZh: "通胀与增长", description: "", indicators: [Self.makeIndicator(id: "PCEPILFE", relation: "positive", percentile3y: 64)]),
            MacroIndicatorSection(id: "official_market", nameZh: "贵金属与跨资产", description: "", indicators: [Self.makeIndicator(id: "GOLD_SILVER_RATIO", relation: "negative", percentile3y: 26)]),
            MacroIndicatorSection(id: "risk_temperature", nameZh: "资金情绪与波动", description: "", indicators: [Self.makeIndicator(id: "GVZCLS", relation: "positive", percentile3y: 22)])
        ])
        let panoramaModel = MacroPanoramaThermometerModel.make(
            temperature: MacroFixtureData.sampleTemperature,
            catalog: sixCatalog
        )

        let pressureShowcase = ScrollView {
            VStack(spacing: 14) {
                MacroTreasuryPressureCard(model: pressureHigh, asOf: "2026-11-21", onShowGuide: {})
                MacroTreasuryPressureCard(model: pressureLow, asOf: "2026-11-21", onShowGuide: {})
                MacroTreasuryPressureCard(model: pressureUnavailable, asOf: "2026-11-21", onShowGuide: {})
            }
            .padding(18)
        }
        .background(GoldTheme.background)

        let panoramaShowcase = ScrollView {
            VStack(spacing: 14) {
                MacroPanoramaThermometerCard(
                    model: panoramaModel,
                    selectedSectionID: "treasury_fiscal",
                    onToggleSection: { _ in },
                    onClearSelection: {},
                    onShowGuide: {}
                )
            }
            .padding(18)
        }
        .background(GoldTheme.background)

        let fixtures: [(String, CGSize?, AnyView)] = [
            ("treasury-pressure-cards", CGSize(width: 393, height: 1120), AnyView(pressureShowcase)),
            ("panorama-thermometer-card", CGSize(width: 393, height: 520), AnyView(panoramaShowcase)),
            ("treasury-pressure-guide-sheet", nil, AnyView(MacroTreasuryPressureGuideSheet(currentLevel: .high))),
            ("panorama-thermometer-guide-sheet", nil, AnyView(MacroPanoramaThermometerGuideSheet(currentLevel: .warm)))
        ]

        for (name, customSize, rootView) in fixtures {
            let window = UIWindow(windowScene: scene)
            if let customSize {
                window.frame = CGRect(origin: .zero, size: customSize)
            }
            let controller = UIHostingController(
                rootView: rootView
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = directory.appendingPathComponent(name + ".png")
            try #require(image.pngData()).write(to: path)
            print("SUPPLEMENTARY_GAUGE_RENDER_ARTIFACT: \(path.path)")
            window.isHidden = true
        }
        previous?.makeKey()
    }
}
