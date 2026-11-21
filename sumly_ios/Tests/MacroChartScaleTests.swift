import Foundation
import Testing
@testable import Sumly

// MARK: - 1. 正值判定与禁用原因

@Test func logScaleEligibilityRequiresAtLeastTwoStrictlyPositiveFinitePoints() {
    // 严格正值（含 < 1 小数、常数、大跨度）
    #expect(MacroChartScale.supportsLogScale([10.0, 20.0]))
    #expect(MacroChartScale.supportsLogScale([0.002, 0.05]))
    #expect(MacroChartScale.supportsLogScale([100.0, 100.0]))
    #expect(MacroChartScale.supportsLogScale([50.0, 100_000.0]))
    #expect(MacroChartScale.logScaleDisabledReason(for: [10.0, 20.0]) == nil)

    // 含 0
    #expect(!MacroChartScale.supportsLogScale([0.0, 10.0]))
    #expect(!MacroChartScale.supportsLogScale([1.5, 0.0, 2.5]))
    #expect(MacroChartScale.logScaleDisabledReason(for: [0.0, 10.0]) == .nonPositiveValues)

    // 含负值（如实际利率、利差、溢价、NFCI、COT）
    #expect(!MacroChartScale.supportsLogScale([-0.85, 1.92]))
    #expect(!MacroChartScale.supportsLogScale([2.0, -1.2, 3.0]))
    #expect(MacroChartScale.logScaleDisabledReason(for: [-0.85, 1.92]) == .nonPositiveValues)
    #expect(MacroChartLogScaleDisabledReason.nonPositiveValues.message == "含零或负值，仅支持线性")

    // 含 NaN / Infinity
    #expect(!MacroChartScale.supportsLogScale([10.0, .nan, 20.0]))
    #expect(!MacroChartScale.supportsLogScale([10.0, .infinity]))
    #expect(!MacroChartScale.supportsLogScale([-.infinity, 10.0]))
    #expect(MacroChartScale.logScaleDisabledReason(for: [10.0, .nan]) == .nonPositiveValues)

    // 空数组与单点
    #expect(!MacroChartScale.supportsLogScale([]))
    #expect(!MacroChartScale.supportsLogScale([36.21]))
    #expect(MacroChartScale.logScaleDisabledReason(for: []) == .insufficientPoints)
    #expect(MacroChartScale.logScaleDisabledReason(for: [36.21]) == .insufficientPoints)
    #expect(MacroChartScale.logScaleDisabledReason(for: [-1.0]) == .nonPositiveValues)
}

@Test func effectiveScaleSafelyFallsBackToLinearWhenInvalid() {
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: [10.0, 20.0]) == .logarithmic)
    #expect(MacroChartScale.effectiveScale(requested: .linear, for: [10.0, 20.0]) == .linear)
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: [0.0, 20.0]) == .linear)
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: [-1.0, 20.0]) == .linear)
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: [10.0, .nan]) == .linear)
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: [10.0]) == .linear)
    #expect(MacroChartScale.effectiveScale(requested: .logarithmic, for: []) == .linear)
}

// MARK: - 2. log10 映射与 pow(10, y) 还原精度

@Test func log10MappingAndPow10RestorationPreserveRatioAndPrecision() throws {
    let scale = MacroChartScale.logarithmic

    // 等比例在 log10 空间等距
    let p10 = try #require(scale.plotValue(10))
    let p100 = try #require(scale.plotValue(100))
    let p1000 = try #require(scale.plotValue(1000))
    #expect(abs((p100 - p10) - (p1000 - p100)) < 1e-12)

    let p001 = try #require(scale.plotValue(0.01))
    let p01 = try #require(scale.plotValue(0.1))
    #expect(abs((p01 - p001) - (p100 - p10)) < 1e-12)

    // 往返精度（涵盖极小值、利率、美债万亿、金价、比特币、百万级）
    let samples: [Double] = [0.0005, 0.02, 0.5, 1.0, 2.5, 37.5, 4_120.0, 98_500.0, 4_900_000.0]
    for raw in samples {
        let mapped = try #require(scale.plotValue(raw))
        let restored = try #require(scale.originalValue(fromPlotValue: mapped))
        #expect(abs(restored - raw) / raw < 1e-12)
    }

    // 非正或非有限值保护
    #expect(scale.plotValue(0) == nil)
    #expect(scale.plotValue(-5) == nil)
    #expect(scale.plotValue(.nan) == nil)
    #expect(scale.plotValue(.infinity) == nil)
    #expect(scale.originalValue(fromPlotValue: .nan) == nil)
    #expect(scale.originalValue(fromPlotValue: .infinity) == nil)

    // 线性映射允许 0 和负值，但拒绝 NaN/Inf
    #expect(MacroChartScale.linear.plotValue(0) == 0)
    #expect(MacroChartScale.linear.plotValue(-2.5) == -2.5)
    #expect(MacroChartScale.linear.plotValue(.nan) == nil)
    #expect(MacroChartScale.linear.originalValue(fromPlotValue: -2.5) == -2.5)
}

// MARK: - 3. Domain 计算与面积图基线安全

@Test func logDomainHandlesSmallSpanLargeSpanAndSubOneValuesSafely() throws {
    // < 1 的小正数：log10 为负，domain 必须完整包住所有点且下界严格低于最小值（确保 AreaMark yStart 不倒挂到 0）
    let subOne = [0.002, 0.008, 0.05]
    let subOneDomain = MacroChartScale.logarithmic.domain(for: subOne)
    #expect(subOneDomain.lowerBound.isFinite && subOneDomain.upperBound.isFinite)
    #expect(subOneDomain.lowerBound < subOneDomain.upperBound)
    #expect(subOneDomain.upperBound < 0) // 两者均 < 1，对数域不应被错误拉到 0
    for v in subOne {
        let y = try #require(MacroChartScale.logarithmic.plotValue(v))
        #expect(subOneDomain.lowerBound < y && y < subOneDomain.upperBound)
    }

    // 小跨度与常数正序列
    for values in [[35.8, 36.2], [36.201, 36.203], [100.0, 100.0], [50.0, 100_000.0], [0.3, 37.5]] {
        let domain = MacroChartScale.logarithmic.domain(for: values)
        #expect(domain.lowerBound.isFinite && domain.upperBound.isFinite)
        #expect(domain.lowerBound < domain.upperBound)
        for v in values {
            let y = try #require(MacroChartScale.logarithmic.plotValue(v))
            #expect(domain.lowerBound < y && y < domain.upperBound)
        }
    }

    // 空/非法数组兜底返回有限区间
    for invalid in [[], [0.0, -1.0, .nan]] as [[Double]] {
        let logDomain = MacroChartScale.logarithmic.domain(for: invalid)
        #expect(logDomain.lowerBound.isFinite && logDomain.upperBound.isFinite && logDomain.lowerBound < logDomain.upperBound)
        let linDomain = MacroChartScale.linear.domain(for: invalid)
        #expect(linDomain.lowerBound.isFinite && linDomain.upperBound.isFinite && linDomain.lowerBound < linDomain.upperBound)
    }

    // includeZeroInLinear 仅在线性模式下包含 0，对数模式绝不把 0 纳入
    let yields = [1.5, 4.5]
    let linContext = MacroChartScaleContext.make(
        values: yields,
        requestedScale: .linear,
        unit: "%",
        includeZeroInLinear: true
    )
    #expect(linContext.domain.lowerBound < 0)

    let logContext = MacroChartScaleContext.make(
        values: yields,
        requestedScale: .logarithmic,
        unit: "%",
        includeZeroInLinear: true
    )
    #expect(logContext.effectiveScale == .logarithmic)
    #expect(logContext.domain.lowerBound > 0) // log10(1.5) ≈ 0.176，加留白仍 > 0
}

// MARK: - 4. Y 轴刻度还原、防重叠与防重复

@Test func logContextRestoresRealBusinessAxisLabelsWithoutDuplicates() {
    // 场景 A：美国国债长期大跨度（$0.3 万亿 ~ $37.5 万亿）
    let debtLong = MacroChartScaleContext.make(
        values: [0.3, 5.5, 18.0, 37.5],
        requestedScale: .logarithmic,
        unit: "trillion_usd",
        desiredTickCount: 4
    )
    #expect(debtLong.effectiveScale == .logarithmic)
    #expect(debtLong.yAxisTicks.count >= 2 && debtLong.yAxisTicks.count <= 4)
    let debtLabels = debtLong.yAxisTicks.map { debtLong.axisLabel(forPlotValue: $0) }
    #expect(Set(debtLabels).count == debtLabels.count)
    #expect(debtLabels.allSatisfy { $0.contains("万亿") && $0.contains("$") })
    // 还原值应在合理美债范围内，绝不能是 log10 原值 1.5
    let debtOriginals = debtLong.yAxisTicks.compactMap { debtLong.originalValue(fromPlotValue: $0) }
    #expect(debtOriginals.max() ?? 0 > 10.0)

    // 场景 B：美债极窄跨度（$35.8 万亿 ~ $36.2 万亿）
    let debtNarrow = MacroChartScaleContext.make(
        values: [35.8, 36.0, 36.2],
        requestedScale: .logarithmic,
        unit: "trillion_usd",
        desiredTickCount: 4
    )
    #expect(debtNarrow.yAxisTicks.count >= 2)
    let debtNarrowLabels = debtNarrow.yAxisTicks.map { debtNarrow.axisLabel(forPlotValue: $0) }
    #expect(Set(debtNarrowLabels).count == debtNarrowLabels.count)
    #expect(debtNarrowLabels.allSatisfy { $0.contains("35.") || $0.contains("36.") })

    // 场景 C：比特币超大跨度（$50 ~ $100,000）
    let btc = MacroChartScaleContext.make(
        values: [50.0, 1_000.0, 20_000.0, 100_000.0],
        requestedScale: .logarithmic,
        unit: "usd",
        desiredTickCount: 4
    )
    #expect(btc.yAxisTicks.count >= 2 && btc.yAxisTicks.count <= 4)
    let btcLabels = btc.yAxisTicks.map { btc.axisLabel(forPlotValue: $0) }
    #expect(Set(btcLabels).count == btcLabels.count)
    #expect(btcLabels.allSatisfy { $0.hasPrefix("$") })
    let btcOriginals = btc.yAxisTicks.compactMap { btc.originalValue(fromPlotValue: $0) }
    #expect((btcOriginals.last ?? 0) >= 10_000)

    // 场景 D：国际金价（$1,800 ~ $4,120）
    let gold = MacroChartScaleContext.make(
        values: [1_800.0, 2_400.0, 3_200.0, 4_120.0],
        requestedScale: .logarithmic,
        unit: "usd/oz",
        desiredTickCount: 3
    )
    #expect(gold.yAxisTicks.count >= 2 && gold.yAxisTicks.count <= 3)
    let goldLabels = gold.yAxisTicks.map { gold.axisLabel(forPlotValue: $0) }
    #expect(Set(goldLabels).count == goldLabels.count)
    #expect(goldLabels.allSatisfy { $0.contains(",") && $0.hasPrefix("$") })

    // 场景 E：< 1 的小正百分比（0.02% ~ 0.08%）
    let smallPct = MacroChartScaleContext.make(
        values: [0.02, 0.05, 0.08],
        requestedScale: .logarithmic,
        unit: "%",
        desiredTickCount: 4
    )
    #expect(smallPct.effectiveScale == .logarithmic)
    let pctLabels = smallPct.yAxisTicks.map { smallPct.axisLabel(forPlotValue: $0) }
    #expect(pctLabels.count >= 2)
    #expect(Set(pctLabels).count == pctLabels.count)
    #expect(pctLabels.allSatisfy { $0.hasSuffix("%") && !$0.hasPrefix("-") })

    // 所有场景均满足：刻度严格递增且落在 domain 内
    for ctx in [debtLong, debtNarrow, btc, gold, smallPct] {
        for tick in ctx.yAxisTicks {
            #expect(ctx.domain.contains(tick))
        }
        for pair in zip(ctx.yAxisTicks, ctx.yAxisTicks.dropFirst()) {
            #expect(pair.0 < pair.1)
        }
    }
}

@Test func axisValueFormattingMatchesBusinessExamples() {
    #expect(MacroChartScale.formatAxisValue(37.5, unit: "trillion_usd", span: 10.0) == "$37.5 万亿")
    #expect(MacroChartScale.formatAxisValue(4_120.0, unit: "usd/oz", span: 2_300.0) == "$4,120")
    #expect(MacroChartScale.formatAxisValue(2.5, unit: "%", span: 3.0) == "2.50%")
    #expect(MacroChartScale.formatAxisValue(100_000.0, unit: "usd", span: 99_950.0) == "$100k")
    #expect(MacroChartScale.formatAxisValue(-0.0, unit: "%", span: 2.0) == "0.00%")
    #expect(MacroChartScale.formatAxisValue(.nan, unit: "usd") == "—")
}

@Test func narrowRangesPreserveDistinctUnroundedAxisLabels() throws {
    // 1. CNY/USD 窄区间 [7.10, 7.25]：步长 0.05 需保留至少 2 位小数，不能舍入撞车为 7.1 / 7.2 / 7.3
    for scale in MacroChartScale.allCases {
        let cny = MacroChartScaleContext.make(
            values: [7.10, 7.16, 7.25],
            requestedScale: scale,
            unit: "ratio",
            desiredTickCount: 4
        )
        #expect(cny.yAxisTicks.count >= 2)
        let labels = cny.yAxisTicks.map { cny.axisLabel(forPlotValue: $0) }
        #expect(Set(labels).count == labels.count)
        for (tick, label) in zip(cny.yAxisTicks, labels) {
            let restored = try #require(cny.originalValue(fromPlotValue: tick))
            let parsed = try #require(Double(label))
            // 格式化后的数值必须忠实贴合网格线真实值，不能出现 0.05 级舍入错位
            #expect(abs(parsed - restored) < 0.01)
        }
    }

    // 2. BTC_USD 窄区间 [90_000, 92_500]：缩放为 k 后步长约 0.5k，不能全舍入撞车为 $91k/$92k
    for scale in MacroChartScale.allCases {
        let btcNarrow = MacroChartScaleContext.make(
            values: [90_000.0, 91_200.0, 92_500.0],
            requestedScale: scale,
            unit: "usd",
            desiredTickCount: 4
        )
        #expect(btcNarrow.yAxisTicks.count >= 2)
        let labels = btcNarrow.yAxisTicks.map { btcNarrow.axisLabel(forPlotValue: $0) }
        #expect(Set(labels).count == labels.count)
        for (tick, label) in zip(btcNarrow.yAxisTicks, labels) {
            let restored = try #require(btcNarrow.originalValue(fromPlotValue: tick))
            #expect(label.hasPrefix("$") && label.hasSuffix("k"))
            let numeric = try #require(Double(label.dropFirst().dropLast())) * 1_000.0
            #expect(abs(numeric - restored) < 100.0)
        }
    }

    // 3. BTC_USD 极窄区间 [98_000, 98_050]：不得退化为单刻度 $98.0k
    for scale in MacroChartScale.allCases {
        let btcUltraNarrow = MacroChartScaleContext.make(
            values: [98_000.0, 98_025.0, 98_050.0],
            requestedScale: scale,
            unit: "usd",
            desiredTickCount: 4
        )
        #expect(btcUltraNarrow.yAxisTicks.count >= 2)
        let labels = btcUltraNarrow.yAxisTicks.map { btcUltraNarrow.axisLabel(forPlotValue: $0) }
        #expect(Set(labels).count == labels.count)
        for (tick, label) in zip(btcUltraNarrow.yAxisTicks, labels) {
            let restored = try #require(btcUltraNarrow.originalValue(fromPlotValue: tick))
            #expect(label.hasPrefix("$") && label.hasSuffix("k"))
            let numeric = try #require(Double(label.dropFirst().dropLast())) * 1_000.0
            #expect(abs(numeric - restored) < 2.0)
        }
    }

    // 4. 紧凑 contracts 窄区间 [180_000, 185_000] 同样保留足够精度不撞车
    let contractsNarrow = MacroChartScaleContext.make(
        values: [180_000.0, 182_500.0, 185_000.0],
        requestedScale: .logarithmic,
        unit: "contracts",
        desiredTickCount: 4
    )
    #expect(contractsNarrow.yAxisTicks.count >= 2)
    let contractLabels = contractsNarrow.yAxisTicks.map { contractsNarrow.axisLabel(forPlotValue: $0) }
    #expect(Set(contractLabels).count == contractLabels.count)
}

@Test func multiSeriesSingleTimestampDisablesLogScaleEvenWhenAllValuesPositive() {
    // 两条曲线各 1 个正值 -> 摊平数组 count == 2，但时间点数 pointCount == 1，必须禁用对数
    let ctx = MacroChartScaleContext.make(
        values: [160_000.0, 30_000.0],
        pointCount: 1,
        requestedScale: .logarithmic,
        unit: "contracts"
    )
    #expect(!ctx.supportsLogScale)
    #expect(ctx.effectiveScale == .linear)
    #expect(ctx.disabledReason == .insufficientPoints)
}

// MARK: - 5. 区间切换自动回退线性（ViewModel 集成测试）

private struct RangeSwitchingMacroService: MacroServicing {
    func fetchTemperature() async throws -> MacroTemperatureReport {
        MacroTemperatureReport(
            asOf: "2026-11-20",
            modelVersion: "v1",
            degraded: false,
            missingFactors: [],
            score: 52.0,
            level: .neutral,
            levelLabel: "温和中性",
            change1d: 0.5,
            change5d: -0.8,
            volatilityAlert: false,
            volatilityNote: "",
            macroRegime: MacroRegime(score: 70, regime: .tailwind, label: "长期宏观顺风", summary: ""),
            actionGuide: MacroActionGuide(
                signal: "neutral_tailwind",
                title: "中性区间 · 多空相对均衡",
                summary: "",
                dcaMultiplier: 1.0,
                dcaLabel: "热度均衡",
                ma200DeviationPct: 6.0,
                ma200Note: "",
                domesticPremiumPct: 0.2,
                domesticPremiumNote: "",
                disclaimer: ""
            ),
            dimensions: []
        )
    }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        let d1 = MacroDateParser.parseDay("2025-11-20")!
        let d2 = MacroDateParser.parseDay("2026-11-20")!
        switch range {
        case .oneYear:
            // 仅 1 个有效金价点 -> 不满足对数条件
            return MacroTemperatureHistory(range: range.rawValue, modelVersion: "v1", points: [
                MacroTemperatureHistoryPoint(dateString: "2026-11-20", date: d2, score: 52, level: .neutral, goldPriceUSD: 4_120)
            ])
        default:
            return MacroTemperatureHistory(range: range.rawValue, modelVersion: "v1", points: [
                MacroTemperatureHistoryPoint(dateString: "2025-11-20", date: d1, score: 45, level: .neutral, goldPriceUSD: 2_650),
                MacroTemperatureHistoryPoint(dateString: "2026-11-20", date: d2, score: 52, level: .neutral, goldPriceUSD: 4_120)
            ])
        }
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        let d1 = MacroDateParser.parseDay("2021-11-20")!
        let d2 = MacroDateParser.parseDay("2026-11-20")!
        let summary = MacroTreasurySummary(
            totalDebtTrillionUSD: 37.5,
            debtChangeYoYTrillion: 2.1,
            debtToGDPPct: 123.0,
            interestToRevenuePct: 18.5,
            fiscalStressScore: 76.0,
            yield10yNominalPct: 4.35,
            yield2yNominalPct: 4.10,
            spread10y2yPct: 0.25,
            yield10yRealPct: 1.95,
            breakeven10yPct: 2.40,
            tltPrice: 91.5,
            goldImpactNote: ""
        )
        let debt = [
            MacroTimePoint(dateString: "2021-11-20", date: d1, value: 28.9),
            MacroTimePoint(dateString: "2026-11-20", date: d2, value: 37.5)
        ]
        // 1y 区间实际利率全正；5y/10y/all 区间包含 2021 年负实际利率
        let realYield: [MacroTimePoint] = range == .oneYear
            ? [
                MacroTimePoint(dateString: "2025-11-20", date: d1, value: 1.65),
                MacroTimePoint(dateString: "2026-11-20", date: d2, value: 1.95)
            ]
            : [
                MacroTimePoint(dateString: "2021-11-20", date: d1, value: -1.02),
                MacroTimePoint(dateString: "2026-11-20", date: d2, value: 1.95)
            ]
        let nominalYield = [
            MacroTimePoint(dateString: "2021-11-20", date: d1, value: 1.55),
            MacroTimePoint(dateString: "2026-11-20", date: d2, value: 4.35)
        ]
        return MacroTreasuryReport(
            asOf: "2026-11-20",
            summary: summary,
            cards: [],
            debtSeries: debt,
            realYieldSeries: realYield,
            nominalYieldSeries: nominalYield
        )
    }

    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog {
        MacroIndicatorsCatalog(sections: [])
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        let d1 = MacroDateParser.parseDay("2021-11-20")!
        let d2 = MacroDateParser.parseDay("2026-11-20")!
        let observations: [MacroTimePoint]
        switch range {
        case .oneYear:
            observations = [
                MacroTimePoint(dateString: "2025-11-20", date: d1, value: 1.75),
                MacroTimePoint(dateString: "2026-11-20", date: d2, value: 2.05)
            ]
        case .threeYears:
            observations = [
                MacroTimePoint(dateString: "2023-11-20", date: d1, value: 1.20),
                MacroTimePoint(dateString: "2026-11-20", date: d2, value: 2.05)
            ]
        default:
            // 5y / 10y / all 含负值
            observations = [
                MacroTimePoint(dateString: "2021-11-20", date: d1, value: -0.95),
                MacroTimePoint(dateString: "2026-11-20", date: d2, value: 2.05)
            ]
        }

        return MacroIndicatorDetail(
            seriesID: seriesID,
            nameZh: "10年期美债实际利率",
            section: "opportunity_cost",
            unit: "%",
            frequency: "daily",
            source: "FRED",
            goldRelation: "negative",
            plainNote: "",
            latestDate: "2026-11-20",
            latestValue: 2.05,
            change5d: nil,
            change20d: nil,
            change3m: nil,
            changeYoY: nil,
            percentile3y: 60,
            range: range.rawValue,
            percentiles: [],
            lastSyncedAt: nil,
            syncStatus: "ok",
            observations: observations
        )
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        let d1 = MacroDateParser.parseDay("2026-11-10")!
        let d2 = MacroDateParser.parseDay("2026-11-17")!
        if range == .oneYear {
            // 仅 1 个时间点且 mmNet / swapNet 均为正，用于验证单时间点不会误开对数
            return MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [
                MacroCotPoint(dateString: "2026-11-17", date: d2, mmLong: 240_000, mmShort: 45_000, mmNet: 195_000, swapLong: 80_000, swapShort: 50_000, swapNet: 30_000, openInterest: 520_000, mmNetRatioPct: 37.5)
            ])
        }
        return MacroCotReport(seriesID: "GOLD_COT", range: range.rawValue, latest: nil, points: [
            MacroCotPoint(dateString: "2026-11-10", date: d1, mmLong: 210_000, mmShort: 50_000, mmNet: 160_000, swapLong: 30_000, swapShort: 180_000, swapNet: -150_000, openInterest: 500_000, mmNetRatioPct: 32.0),
            MacroCotPoint(dateString: "2026-11-17", date: d2, mmLong: 240_000, mmShort: 45_000, mmNet: 195_000, swapLong: 32_000, swapShort: 210_000, swapNet: -178_000, openInterest: 520_000, mmNetRatioPct: 37.5)
        ])
    }
}

@MainActor @Test func indicatorDetailAutoFallsBackToLinearWhenRangeIntroducesNegativeValues() async {
    let model = MacroIndicatorDetailViewModel(seriesID: "DFII10", service: RangeSwitchingMacroService())

    // 先切到 1y（严格正值）并开启对数
    await model.selectRange(.oneYear)
    #expect(model.supportsLogScale)
    model.setChartScale(.logarithmic)
    #expect(model.chartScale == .logarithmic)
    #expect(model.effectiveChartScale == .logarithmic)

    // 切到 3y（仍全为正）保持对数
    await model.selectRange(.threeYears)
    #expect(model.supportsLogScale)
    #expect(model.chartScale == .logarithmic)

    // 切到 5y（引入负值 -0.95%）自动回退为线性，且禁止重新开启对数
    await model.selectRange(.fiveYears)
    #expect(!model.supportsLogScale)
    #expect(model.chartScale == .linear)
    #expect(model.effectiveChartScale == .linear)
    #expect(model.chartScaleContext.disabledReason == .nonPositiveValues)

    model.setChartScale(.logarithmic)
    #expect(model.chartScale == .linear)
    #expect(model.effectiveChartScale == .linear)
}

@MainActor @Test func dashboardAutoFallsBackTreasuryYieldAndGoldScalesIndependentlyOnRangeSwitch() async {
    let model = MacroDashboardViewModel(service: RangeSwitchingMacroService())

    // 1. 美国国债：1y 下美债规模与 10Y 利率均全正，可同时开启对数
    await model.selectTreasuryRange(.oneYear)
    model.setTreasuryDebtScale(.logarithmic)
    model.setTreasuryYieldScale(.logarithmic)
    #expect(model.treasuryDebtScale == .logarithmic)
    #expect(model.treasuryYieldScale == .logarithmic)

    // 切换到 10y：利率出现负值自动回退线性，美债规模仍全正继续保持对数
    await model.selectTreasuryRange(.tenYears)
    #expect(model.treasuryDebtScale == .logarithmic)
    #expect(model.treasuryDebtScaleContext.effectiveScale == .logarithmic)
    #expect(model.treasuryYieldScale == .linear)
    #expect(model.treasuryYieldScaleContext.effectiveScale == .linear)
    #expect(model.treasuryYieldScaleContext.disabledReason == .nonPositiveValues)

    // 2. 黄金温度页国际金价：3y 支持对数，切到仅单点的 1y 自动回退线性
    await model.loadTemperatureHistory(range: .threeYears)
    model.setTemperatureGoldPriceScale(.logarithmic)
    #expect(model.temperatureGoldPriceScale == .logarithmic)

    await model.selectTemperatureRange(.oneYear)
    #expect(model.temperatureGoldPriceScale == .linear)
    #expect(model.temperatureGoldPriceScaleContext.disabledReason == .insufficientPoints)

    // 3. CFTC COT 含负值（swapNet < 0），无法切换对数
    await model.loadCot(range: .threeYears)
    model.setCotScale(.logarithmic)
    #expect(model.cotScale == .linear)
    #expect(model.cotScaleContext.disabledReason == .nonPositiveValues)

    // 4. CFTC COT 单时间点即使两值均为正，仍不可启用对数且原因为数据点不足
    await model.selectCotRange(.oneYear)
    model.setCotScale(.logarithmic)
    #expect(model.cotScale == .linear)
    #expect(!model.cotScaleContext.supportsLogScale)
    #expect(model.cotScaleContext.disabledReason == .insufficientPoints)
}
