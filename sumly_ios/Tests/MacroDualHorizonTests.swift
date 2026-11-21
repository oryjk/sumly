import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite("MacroDualHorizon Tests")
struct MacroDualHorizonTests {
    private static let extraForbiddenWords: [String] = [
        "偏暖", "操作指南针", "逢低", "加配", "定投", "加仓", "减仓", "止盈",
        "建仓", "追高", "抄底", "知识星球", "付费社群", "建议", "适合", "划算",
        "黄金坑", "安全垫", "分批", "仓位", "买入", "卖出", "放慢节奏", "防守",
        "试探", "便宜", "贵", "买点", "卖点", "机会", "配置", "入场", "离场"
    ]

    @Test func allFifteenCombinationsAreCompleteObjectiveAndFreeOfWarmConflict() {
        let expectedPatterns: [MacroTemperatureLevel: [MacroRegimeKind: String]] = [
            .freezing: [.tailwind: "极冷长强", .neutral: "极冷长平", .headwind: "极冷长弱"],
            .cool: [.tailwind: "短冷长强", .neutral: "短冷长平", .headwind: "短冷长弱"],
            .neutral: [.tailwind: "短平长强", .neutral: "双端中性", .headwind: "短平长弱"],
            .warm: [.tailwind: "短热长强", .neutral: "短热长平", .headwind: "短热长弱"],
            .hot: [.tailwind: "过热长强", .neutral: "过热长平", .headwind: "过热长弱"]
        ]

        let sampleShortScore: [MacroTemperatureLevel: Double] = [
            .freezing: 12.4,
            .cool: 32.3,
            .neutral: 50.0,
            .warm: 71.6,
            .hot: 89.2
        ]
        let sampleLongScore: [MacroRegimeKind: Double] = [
            .tailwind: 71.0,
            .neutral: 50.0,
            .headwind: 26.4
        ]

        var count = 0
        for level in MacroTemperatureLevel.allCases {
            for regime in MacroRegimeKind.allCases {
                count += 1
                let shortScore = sampleShortScore[level] ?? 50.0
                let longScore = sampleLongScore[regime] ?? 50.0

                let summary = MacroPresentation.dualHorizonSummary(
                    level: level,
                    shortScore: shortScore,
                    regime: regime,
                    longScore: longScore
                )

                #expect(summary.shortTermLevel == level)
                #expect(summary.shortTermLevelLabel == level.defaultLabel)
                #expect(summary.longTermRegime == regime)
                #expect(summary.longTermState == regime.defaultLabel)
                #expect(summary.longTermScoreText == "\(Int(longScore.rounded()))分")
                #expect(summary.combinedPatternLabel == expectedPatterns[level]?[regime])
                #expect(summary.combinedPatternLabel.count == 4)

                // 首页双行短句长度严格 ≤ 15 字，保证 375pt 小屏排版清晰不拥挤
                #expect(summary.shortTermPlainNote.count <= 15)
                #expect(summary.longTermPlainNote.count <= 15)

                let allFields = [
                    summary.shortTermLevelLabel,
                    summary.shortTermCompactTitle,
                    summary.shortTermState,
                    summary.shortTermCrowding,
                    summary.shortTermPlainNote,
                    summary.shortTermDetailNote,
                    summary.longTermScoreText,
                    summary.longTermState,
                    summary.longTermPlainNote,
                    summary.longTermDetailNote,
                    summary.combinedPatternLabel,
                    summary.combinedSummary
                ]

                for field in allFields {
                    #expect(!field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    #expect(!MacroPresentation.containsAdvisoryTerms(field), "文案「\(field)」触发投顾关键词")
                    for word in Self.extraForbiddenWords {
                        #expect(!field.contains(word), "文案「\(field)」不应包含禁用词「\(word)」")
                    }
                }
            }
        }

        #expect(count == 15)
    }

    @Test func longTermRegimeLabelsAndColorsUseIndependentGoldThemeTokens() {
        #expect(MacroRegimeKind.tailwind.defaultLabel == "支撑偏强")
        #expect(MacroRegimeKind.neutral.defaultLabel == "背景中性")
        #expect(MacroRegimeKind.headwind.defaultLabel == "支撑偏弱")

        for regime in MacroRegimeKind.allCases {
            #expect(!regime.defaultLabel.contains("偏暖"))
            #expect(!MacroPresentation.containsAdvisoryTerms(regime.defaultLabel))
        }

        #expect(MacroPresentation.regimeColor(for: .tailwind) == GoldTheme.gold)
        #expect(MacroPresentation.regimeColor(for: .neutral) == GoldTheme.textSecondary)
        #expect(MacroPresentation.regimeColor(for: .headwind) == GoldTheme.tempFreezing)
    }

    @Test func expandedAdvisoryKeywordsCatchValuationAndTimingTerms() {
        let samples = [
            "当前金价比较便宜",
            "目前位置偏贵",
            "右侧买点出现",
            "已到阶段卖点",
            "迎来上车机会",
            "适合长期配置",
            "可以分批入场",
            "注意择机离场"
        ]
        for text in samples {
            #expect(MacroPresentation.containsAdvisoryTerms(text), "应识别投顾/估值词：\(text)")
        }
    }

    @Test func dualHorizonSummaryCompletelyBlocksLegacyWarmAndAdvisoryBackendFields() {
        let legacyReport = MacroTemperatureReport(
            asOf: "2026-11-21",
            modelVersion: "v1",
            degraded: false,
            missingFactors: [],
            score: 32.3,
            level: .cool,
            levelLabel: "偏冷蓄势",
            change1d: -0.9,
            change5d: -2.4,
            volatilityAlert: true,
            volatilityNote: "建议逢低分批加仓配置",
            macroRegime: MacroRegime(
                score: 71.0,
                regime: .tailwind,
                label: "宏观偏暖",
                summary: "长期宏观偏暖，逢低配置机会难得。"
            ),
            actionGuide: MacroActionGuide(
                signal: "cool_tailwind",
                title: "偏冷区间 · 宏观偏暖",
                summary: "当前整体呈现“宏观偏暖、短线偏冷”特征，适合定投 1.2x 逢低加配。",
                dcaMultiplier: 1.2,
                dcaLabel: "定投 1.2x",
                ma200DeviationPct: -3.12,
                ma200Note: "低于200日均线3.12%，短期安全垫较厚。",
                domesticPremiumPct: -0.42,
                domesticPremiumNote: "国内折价较便宜，划算。",
                disclaimer: ""
            ),
            dimensions: []
        )

        let dual = MacroPresentation.dualHorizonSummary(for: legacyReport)
        #expect(dual.shortTermLevelLabel == "偏冷区间")
        #expect(dual.shortTermCompactTitle == "偏冷 · 拥挤度低")
        #expect(dual.shortTermState == "交投偏冷")
        #expect(dual.longTermState == "支撑偏强")
        #expect(dual.longTermScoreText == "71分")
        #expect(dual.combinedPatternLabel == "短冷长强")

        let fields = [
            dual.shortTermLevelLabel,
            dual.shortTermCompactTitle,
            dual.shortTermState,
            dual.shortTermCrowding,
            dual.shortTermPlainNote,
            dual.shortTermDetailNote,
            dual.longTermScoreText,
            dual.longTermState,
            dual.longTermPlainNote,
            dual.longTermDetailNote,
            dual.combinedPatternLabel,
            dual.combinedSummary
        ]
        for field in fields {
            #expect(!field.contains("偏暖"))
            #expect(!field.contains("蓄势"))
            #expect(!MacroPresentation.containsAdvisoryTerms(field))
        }

        // 伴随高波动兜底与免责声明兜底同样屏蔽旧版投顾文案
        let volNote = MacroPresentation.objectiveVolatilityNote(for: legacyReport)
        let ma200Note = MacroPresentation.objectiveMa200Note(for: legacyReport.actionGuide)
        let premiumNote = MacroPresentation.objectiveDomesticPremiumNote(for: legacyReport.actionGuide)
        for text in [volNote, ma200Note, premiumNote] {
            #expect(!text.isEmpty)
            #expect(!MacroPresentation.containsAdvisoryTerms(text))
        }
    }

    @Test func dualHorizonSummaryClampsInvalidScoresAndConformsToSendable() {
        let low = MacroPresentation.dualHorizonSummary(level: .freezing, shortScore: -12, regime: .headwind, longScore: -5)
        #expect(low.shortTermScore == 0)
        #expect(low.longTermScore == 0)
        #expect(low.longTermScoreText == "0分")

        let high = MacroPresentation.dualHorizonSummary(level: .hot, shortScore: 145, regime: .tailwind, longScore: 120)
        #expect(high.shortTermScore == 100)
        #expect(high.longTermScore == 100)
        #expect(high.longTermScoreText == "100分")

        let nan = MacroPresentation.dualHorizonSummary(level: .neutral, shortScore: .nan, regime: .neutral, longScore: .infinity)
        #expect(nan.shortTermScore == 0)
        #expect(nan.longTermScore == 0)
        #expect(nan.longTermScoreText == "0分")

        let sendableCheck: any Sendable = high
        #expect(sendableCheck is MacroDualHorizonSummary)
    }

    @MainActor @Test func renderDualHorizonHomeCardAndDashboardForVisualReview() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-dual-horizon-review")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let report = Self.makeSampleReport(
            score: 32.3,
            level: .cool,
            regime: .tailwind,
            regimeScore: 71.0,
            volatilityAlert: false,
            degraded: false
        )
        let alertReport = Self.makeSampleReport(
            score: 86.4,
            level: .hot,
            regime: .headwind,
            regimeScore: 28.0,
            volatilityAlert: true,
            degraded: true
        )
        let treasury = MacroTreasurySummary(
            totalDebtTrillionUSD: 36.22,
            debtChangeYoYTrillion: 2.12,
            debtToGDPPct: 122.9,
            interestToRevenuePct: 18.4,
            fiscalStressScore: 76.0,
            yield10yNominalPct: 4.32,
            yield2yNominalPct: 4.18,
            spread10y2yPct: 0.14,
            yield10yRealPct: 1.92,
            breakeven10yPct: 2.40,
            tltPrice: 91.25,
            goldImpactNote: "美债总规模与财政付息压力处于近 3 年偏高位。"
        )

        let homeCardsView = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("首页卡片 · 典型态（32.3° 偏冷 × 71分 支撑偏强）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)

                GoldTemperatureCard(
                    temperature: report,
                    treasury: treasury,
                    isLoading: false,
                    errorMessage: nil,
                    onRetry: {},
                    onOpenDashboard: {}
                )

                Text("首页卡片 · 高波动 + 降级（86.4° 极热 × 28分 支撑偏弱）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .padding(.top, 2)

                GoldTemperatureCard(
                    temperature: alertReport,
                    treasury: treasury,
                    isLoading: false,
                    errorMessage: nil,
                    onRetry: {},
                    onOpenDashboard: {}
                )
            }
            .padding(18)
        }
        .background(GoldTheme.background)

        let service = VisualReviewMacroService(report: report, treasury: treasury)
        let dashboardModel = MacroDashboardViewModel(service: service)
        await dashboardModel.loadDashboard()

        let dashboardView = NavigationStack {
            MacroDashboardView(model: dashboardModel, service: service)
        }

        let guideSheetView = MacroTemperatureGuideSheet(
            help: report.resolvedGuideHelp,
            disclaimer: MacroPresentation.objectiveDisclaimer(for: report.actionGuide),
            currentLevel: report.level
        )

        let fixtures: [(String, CGSize?, AnyView)] = [
            ("dual-horizon-home-cards", nil, AnyView(homeCardsView)),
            ("dual-horizon-home-375pt", CGSize(width: 375, height: 640), AnyView(homeCardsView)),
            ("dual-horizon-dashboard", CGSize(width: 402, height: 1120), AnyView(dashboardView)),
            ("dual-horizon-guide-sheet", nil, AnyView(guideSheetView))
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
            print("DUAL_HORIZON_RENDER_ARTIFACT: \(path.path)")
            window.isHidden = true
        }
        previous?.makeKey()
    }

    private static func makeSampleReport(
        score: Double,
        level: MacroTemperatureLevel,
        regime: MacroRegimeKind,
        regimeScore: Double,
        volatilityAlert: Bool,
        degraded: Bool
    ) -> MacroTemperatureReport {
        MacroTemperatureReport(
            asOf: "2026-11-21",
            modelVersion: "v1",
            degraded: degraded,
            missingFactors: degraded ? ["domestic_premium"] : [],
            score: score,
            level: level,
            levelLabel: "偏冷蓄势",
            change1d: -0.9,
            change5d: -2.4,
            volatilityAlert: volatilityAlert,
            volatilityNote: volatilityAlert ? "黄金隐含波动率处于近 3 年 91% 高位，历史同期短期振幅往往放大。" : "",
            macroRegime: MacroRegime(
                score: regimeScore,
                regime: regime,
                label: "宏观偏暖",
                summary: "旧版后端宏观偏暖摘要不应透传。"
            ),
            actionGuide: MacroActionGuide(
                signal: "cool_tailwind",
                title: "偏冷区间 · 宏观偏暖",
                summary: "旧版后端混合摘要不应透传。",
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
                    summary: "价格回踩 200 日均线下方，短期动量偏温和。"
                ),
                MacroTemperatureDimension(
                    key: "positioning",
                    name: "期货持仓拥挤度",
                    weight: 0.25,
                    score: 34.0,
                    available: true,
                    status: "cool",
                    summary: "CFTC 基金净多头占比处于近 3 年偏低分位。"
                )
            ],
            guideHelp: MacroTemperatureGuideHelp(
                title: "黄金温度计说明",
                methodology: MacroTemperatureGuideHelp.defaultGuide.methodology,
                levels: MacroTemperatureGuideHelp.defaultGuide.levels,
                officialAccountName: "何止编程",
                officialAccountNote: MacroTemperatureGuideHelp.defaultOfficialAccountNote
            )
        )
    }
}

private struct VisualReviewMacroService: MacroServicing {
    let report: MacroTemperatureReport
    let treasury: MacroTreasurySummary

    func fetchTemperature() async throws -> MacroTemperatureReport { report }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        let day1 = MacroDateParser.parseDay("2026-11-18")!
        let day2 = MacroDateParser.parseDay("2026-11-19")!
        let day3 = MacroDateParser.parseDay("2026-11-20")!
        return MacroTemperatureHistory(
            range: range.rawValue,
            modelVersion: "v1",
            points: [
                MacroTemperatureHistoryPoint(dateString: "2026-11-18", date: day1, score: 38.2, level: .cool, goldPriceUSD: 2610),
                MacroTemperatureHistoryPoint(dateString: "2026-11-19", date: day2, score: 34.7, level: .cool, goldPriceUSD: 2595),
                MacroTemperatureHistoryPoint(dateString: "2026-11-20", date: day3, score: report.score, level: report.level, goldPriceUSD: 2588)
            ]
        )
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        MacroTreasuryReport(
            asOf: "2026-11-21",
            summary: treasury,
            cards: [],
            debtSeries: [],
            realYieldSeries: [],
            nominalYieldSeries: []
        )
    }

    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog {
        MacroIndicatorsCatalog(sections: [])
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        MacroIndicatorDetail(
            seriesID: seriesID,
            nameZh: "10年期美债实际利率",
            section: "opportunity_cost",
            unit: "%",
            frequency: "daily",
            source: "FRED",
            goldRelation: "negative",
            plainNote: "实际利率变化影响黄金持有成本。",
            latestDate: "2026-11-21",
            latestValue: 1.92,
            change5d: -0.04,
            change20d: -0.10,
            change3m: -0.18,
            changeYoY: -0.32,
            percentile3y: 58.0,
            range: range.rawValue,
            percentiles: [],
            lastSyncedAt: "2026-11-21T08:00:00Z",
            syncStatus: "ok",
            observations: []
        )
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [])
    }
}
