import SwiftUI

// MARK: - 1. 美债财政压力表纯逻辑模型

enum MacroTreasuryPressureLevel: String, Sendable, CaseIterable, Equatable, Hashable, Identifiable {
    case low
    case moderate
    case elevated
    case high
    case extreme

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: L10n.tr("压力偏低")
        case .moderate: L10n.tr("温和区间")
        case .elevated: L10n.tr("压力偏高")
        case .high: L10n.tr("高压区间")
        case .extreme: L10n.tr("极高压力")
        }
    }

    var rangeText: String {
        switch self {
        case .low: "0 ~ 25"
        case .moderate: "25 ~ 45"
        case .elevated: "45 ~ 65"
        case .high: "65 ~ 80"
        case .extreme: "80 ~ 100"
        }
    }

    var guideDescription: String {
        switch self {
        case .low:
            L10n.tr("债务率与付息负担处于偏低水平，财政空间相对充裕。")
        case .moderate:
            L10n.tr("偿债支出与赤字规模处于常规区间，美元长期信用压力相对缓和。")
        case .elevated:
            L10n.tr("债务扩张与付息占比逐步抬升，财政空间边际收窄，信用承压初显。")
        case .high:
            L10n.tr("付息支出占财政收入比与债务率处于高位，长期信用压力较显著。")
        case .extreme:
            L10n.tr("债务规模、赤字率与付息负担同步处于历史极高位，长期信用压力凸显。")
        }
    }

    var color: Color {
        switch self {
        case .low: GoldTheme.tempFreezing
        case .moderate: GoldTheme.goldSoft
        case .elevated: GoldTheme.gold
        case .high: GoldTheme.tempWarm
        case .extreme: GoldTheme.tempHot
        }
    }

    static func from(score: Double) -> MacroTreasuryPressureLevel {
        guard score.isFinite else { return .elevated }
        let clamped = MacroPresentation.clampedTemperatureScore(score)
        switch clamped {
        case ..<25: return .low
        case 25..<45: return .moderate
        case 45..<65: return .elevated
        case 65..<80: return .high
        default: return .extreme
        }
    }
}

struct MacroTreasuryPressureDriver: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let valueText: String
    let hasValue: Bool
}

struct MacroTreasuryPressureModel: Sendable, Equatable {
    enum ScoreSource: Sendable, Equatable {
        case summary
        case cardFallback
        case unavailable
    }

    let score: Double?
    let scoreSource: ScoreSource
    let level: MacroTreasuryPressureLevel?
    let drivers: [MacroTreasuryPressureDriver]
    let plainNote: String

    var hasScore: Bool { score != nil }

    var scoreText: String {
        guard let score else { return "—" }
        return String(format: "%.1f", score)
    }

    var levelLabel: String {
        level?.label ?? L10n.tr("待同步")
    }

    static func make(from report: MacroTreasuryReport) -> MacroTreasuryPressureModel {
        make(summary: report.summary, cards: report.cards)
    }

    static func make(
        summary: MacroTreasurySummary,
        cards: [MacroIndicatorSummary] = []
    ) -> MacroTreasuryPressureModel {
        let resolvedScore: Double?
        let source: ScoreSource

        if let s = summary.fiscalStressScore, s.isFinite {
            resolvedScore = MacroPresentation.clampedTemperatureScore(s)
            source = .summary
        } else if let fallback = cardLatestValue(in: cards, matching: ["FISCAL_STRESS"]) {
            resolvedScore = MacroPresentation.clampedTemperatureScore(fallback)
            source = .cardFallback
        } else {
            resolvedScore = nil
            source = .unavailable
        }

        let level = resolvedScore.map(MacroTreasuryPressureLevel.from(score:))

        let debtToGDP = finiteOrNil(summary.debtToGDPPct)
            ?? cardLatestValue(in: cards, matching: ["GFDEGDQ188S"])
        let interestToRevenue = finiteOrNil(summary.interestToRevenuePct)
            ?? cardLatestValue(in: cards, matching: ["INTEREST_RATIO"])
        let totalDebt = finiteOrNil(summary.totalDebtTrillionUSD)
            ?? cardLatestValue(in: cards, matching: ["US_DEBT_DAILY", "GFDEBTN"])

        let drivers: [MacroTreasuryPressureDriver] = [
            MacroTreasuryPressureDriver(
                id: "debt_to_gdp",
                title: L10n.tr("债务 / GDP"),
                valueText: MacroPresentation.formatPercent(debtToGDP),
                hasValue: debtToGDP != nil
            ),
            MacroTreasuryPressureDriver(
                id: "interest_to_revenue",
                title: L10n.tr("付息 / 财政收入"),
                valueText: MacroPresentation.formatPercent(interestToRevenue),
                hasValue: interestToRevenue != nil
            ),
            MacroTreasuryPressureDriver(
                id: "total_debt",
                title: L10n.tr("国债总规模"),
                valueText: MacroPresentation.formatTrillionUSD(totalDebt),
                hasValue: totalDebt != nil
            )
        ]

        return MacroTreasuryPressureModel(
            score: resolvedScore,
            scoreSource: source,
            level: level,
            drivers: drivers,
            plainNote: objectivePlainNote(for: level)
        )
    }

    static func objectivePlainNote(for level: MacroTreasuryPressureLevel?) -> String {
        guard let level else {
            return L10n.tr("财政压力指数待同步，待美国财政部与美联储基础数据更新后自动计算呈现。")
        }
        switch level {
        case .low:
            return L10n.tr("当前美国财政压力处于低位，债务与付息负担相对可控，美元长期信用面较为平稳。")
        case .moderate:
            return L10n.tr("当前美国财政压力处于温和区间，偿债支出与债务比率处于常规范围，长期信用压力相对缓和。")
        case .elevated:
            return L10n.tr("当前美国财政压力处于偏高区间，债务扩张与付息支出逐步抬升，黄金的长期信用对冲属性受关注。")
        case .high:
            return L10n.tr("当前美国财政压力处于高压区间，联邦偿债负担与美元信用承压较明显，反映黄金长期信用属性偏强。")
        case .extreme:
            return L10n.tr("当前美国财政压力处于极高区间，债务规模与利息支出占比均处历史高位，美元信用压力持续凸显。")
        }
    }

    private static func finiteOrNil(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func cardLatestValue(
        in cards: [MacroIndicatorSummary],
        matching seriesIDs: [String]
    ) -> Double? {
        for target in seriesIDs {
            if let card = cards.first(where: { $0.seriesID.caseInsensitiveCompare(target) == .orderedSame }),
               let value = card.latestValue,
               value.isFinite {
                return value
            }
        }
        return nil
    }
}

enum MacroTreasuryPressureGuideContent {
    static var title: String { L10n.tr("美债财政压力表说明") }
    static var badgeText: String { L10n.tr("3 项财政因子 · 0~100") }
    static var methodology: String { L10n.tr("美债财政压力指数（0~100）由联邦付息支出占财政收入比、财政赤字占 GDP 比例与联邦债务占 GDP 比例非线性加权合成，用于客观刻画美国财政偿债负担与美元长期信用压力水平。") }
    static var goldCreditRelationTitle: String { L10n.tr("与黄金的长期信用关联") }
    static var goldCreditRelationNote: String { L10n.tr("黄金作为非主权实物资产，在历史上往往与美元长期财政信用周期呈反向波动。当联邦债务规模扩张且付息占比走高时，市场对法币长期购买力与偿债可持续性的关注度上升，本表仅做客观状态展示。") }
}

// MARK: - 2. 美债财政压力表半圆弧纯几何模型

struct MacroTreasuryPressureGaugeGeometry: Sendable, Equatable {
    /// 压力表盘总跨度：210°（165° 顺时针扫至 375°），中点严格位于正上方 270°。
    static let sweepAngleDegrees: Double = 210.0
    static let arcSpan: Double = sweepAngleDegrees / 360.0
    static let startAngleDegrees: Double = 270.0 - sweepAngleDegrees / 2.0 // 165°
    static let endAngleDegrees: Double = 270.0 + sweepAngleDegrees / 2.0   // 375°
    static let minimumTrim: Double = 0.001
    static let majorTickValues: [Double] = [0, 25, 50, 75, 100]

    let score: Double?
    let diameter: CGFloat
    let lineWidth: CGFloat

    init(score: Double?, diameter: CGFloat = 212, lineWidth: CGFloat = 14) {
        self.score = score
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    var strokeInset: CGFloat { lineWidth / 2 }
    var trackRadius: CGFloat { (diameter - lineWidth) / 2 }
    var outerStrokeRadius: CGFloat { trackRadius + lineWidth / 2 }
    var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }
    var dotDiameter: CGFloat { 13 }
    var dotBorderWidth: CGFloat { 2.8 }

    var tickOuterRadius: CGFloat { trackRadius - lineWidth / 2 - 5 }
    var tickInnerRadius: CGFloat { tickOuterRadius - 6 }
    var pointerBaseRadius: CGFloat { tickInnerRadius - 7 }

    var hasScore: Bool {
        guard let score else { return false }
        return score.isFinite
    }

    var clampedScore: Double {
        guard let score, score.isFinite else { return 0 }
        return MacroPresentation.clampedTemperatureScore(score)
    }

    var rawProgress: Double {
        clampedScore / 100.0
    }

    /// 共享有效进度：确保弧线终点、径向指针与指示圆点圆心角度严格一致。
    var effectiveProgress: Double {
        max(Self.minimumTrim / Self.arcSpan, rawProgress)
    }

    var trackTrimEnd: Double {
        Self.arcSpan
    }

    var activeTrimEnd: Double {
        Self.arcSpan * effectiveProgress
    }

    var activeArcEndAngleDegrees: Double {
        Self.startAngleDegrees + activeTrimEnd * 360.0
    }

    var indicatorAngleDegrees: Double {
        Self.startAngleDegrees + Self.sweepAngleDegrees * effectiveProgress
    }

    func angleDegrees(forScore value: Double) -> Double {
        let clamped = MacroPresentation.clampedTemperatureScore(value)
        return Self.startAngleDegrees + Self.sweepAngleDegrees * (clamped / 100.0)
    }

    func point(atAngleDegrees degrees: Double, radius: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180.0
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    func pointOnTrack(atAngleDegrees degrees: Double) -> CGPoint {
        point(atAngleDegrees: degrees, radius: trackRadius)
    }

    var startPoint: CGPoint {
        pointOnTrack(atAngleDegrees: Self.startAngleDegrees)
    }

    var endPoint: CGPoint {
        pointOnTrack(atAngleDegrees: Self.endAngleDegrees)
    }

    var activeArcEndPoint: CGPoint {
        pointOnTrack(atAngleDegrees: activeArcEndAngleDegrees)
    }

    var indicatorCenter: CGPoint {
        pointOnTrack(atAngleDegrees: indicatorAngleDegrees)
    }

    var visibleHeight: CGFloat {
        let bottomStrokeY = max(startPoint.y, endPoint.y) + lineWidth / 2
        return ceil(bottomStrokeY + 18)
    }
}

// MARK: - 3. 宏观全景温度计纯逻辑模型

struct MacroPanoramaPillar: Sendable, Equatable, Identifiable {
    let id: String
    let nameZh: String
    let score: Double?
    let level: MacroTemperatureLevel?
    let validIndicatorCount: Int
    let totalIndicatorCount: Int

    var localizedName: String {
        MacroLocalization.sectionName(id: id, fallback: nameZh)
    }

    var shortStatusLabel: String {
        guard let level else { return L10n.tr("待同步") }
        switch level {
        case .freezing: return L10n.tr("极冷")
        case .cool: return L10n.tr("偏冷")
        case .neutral: return L10n.tr("中性")
        case .warm: return L10n.tr("偏热")
        case .hot: return L10n.tr("极热")
        }
    }

    var scoreText: String {
        guard let score else { return "—" }
        return "\(Int(score.rounded()))°"
    }
}

struct MacroPanoramaThermometerModel: Sendable, Equatable {
    enum ScoreSource: Sendable, Equatable {
        case macroRegime
        case catalogFallback
        case unavailable
    }

    let score: Double?
    let scoreSource: ScoreSource
    let level: MacroTemperatureLevel?
    let pillars: [MacroPanoramaPillar]
    let summaryText: String
    let hotPillarCount: Int
    let neutralPillarCount: Int
    let coldPillarCount: Int

    var hasScore: Bool { score != nil }
    var hasAnyData: Bool { hasScore || !pillars.isEmpty }

    var levelLabel: String {
        level?.defaultLabel ?? L10n.tr("待同步")
    }

    var sourceBadgeText: String {
        switch scoreSource {
        case .macroRegime: L10n.tr("长期宏观同源")
        case .catalogFallback: L10n.tr("板块分位合成")
        case .unavailable: L10n.tr("待数据同步")
        }
    }

    static func make(
        temperature: MacroTemperatureReport?,
        catalog: MacroIndicatorsCatalog?
    ) -> MacroPanoramaThermometerModel {
        let sections = catalog?.sections ?? []
        let pillars = sections.map(makePillar(from:))

        let resolvedScore: Double?
        let source: ScoreSource

        if let report = temperature,
           report.hasAvailableData,
           report.macroRegime.score.isFinite {
            resolvedScore = MacroPresentation.clampedTemperatureScore(report.macroRegime.score)
            source = .macroRegime
        } else if let fallback = catalogFallbackScore(from: sections) {
            resolvedScore = fallback
            source = .catalogFallback
        } else {
            resolvedScore = nil
            source = .unavailable
        }

        let level = resolvedScore.map(MacroTemperatureLevel.from(score:))

        var hotCount = 0
        var neutralCount = 0
        var coldCount = 0
        for pillar in pillars {
            guard let pillarLevel = pillar.level else { continue }
            switch pillarLevel {
            case .warm, .hot: hotCount += 1
            case .neutral: neutralCount += 1
            case .freezing, .cool: coldCount += 1
            }
        }

        let summary = buildSummary(
            level: level,
            scoredPillarCount: hotCount + neutralCount + coldCount,
            hotCount: hotCount,
            neutralCount: neutralCount,
            coldCount: coldCount
        )

        return MacroPanoramaThermometerModel(
            score: resolvedScore,
            scoreSource: source,
            level: level,
            pillars: pillars,
            summaryText: summary,
            hotPillarCount: hotCount,
            neutralPillarCount: neutralCount,
            coldPillarCount: coldCount
        )
    }

    private enum NormalizedRelation {
        case positive
        case negative
        case neutral
    }

    private enum ClassifiedPercentile {
        case directional(Double)
        case neutral(Double)
    }

    private static func normalizedRelation(_ raw: String) -> NormalizedRelation {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "positive", "bullish", "same":
            return .positive
        case "negative", "inverse", "bearish":
            return .negative
        default:
            return .neutral
        }
    }

    private static func classifyPercentile(for indicator: MacroIndicatorSummary) -> ClassifiedPercentile? {
        guard let raw = indicator.percentile3y, raw.isFinite else { return nil }
        let clamped = MacroPresentation.clampedTemperatureScore(raw)
        switch normalizedRelation(indicator.goldRelation) {
        case .positive:
            return .directional(clamped)
        case .negative:
            return .directional(100.0 - clamped)
        case .neutral:
            return .neutral(clamped)
        }
    }

    private static func aggregateIndicators(_ indicators: [MacroIndicatorSummary]) -> (score: Double, count: Int)? {
        var directionalValues: [Double] = []
        var neutralValues: [Double] = []

        for indicator in indicators {
            guard let classified = classifyPercentile(for: indicator) else { continue }
            switch classified {
            case .directional(let value):
                directionalValues.append(value)
            case .neutral(let value):
                neutralValues.append(value)
            }
        }

        if !directionalValues.isEmpty {
            let mean = directionalValues.reduce(0, +) / Double(directionalValues.count)
            return (MacroPresentation.clampedTemperatureScore(mean), directionalValues.count)
        }

        if !neutralValues.isEmpty {
            let mean = neutralValues.reduce(0, +) / Double(neutralValues.count)
            return (MacroPresentation.clampedTemperatureScore(mean), neutralValues.count)
        }

        return nil
    }

    private static func makePillar(from section: MacroIndicatorSection) -> MacroPanoramaPillar {
        let aggregated = aggregateIndicators(section.indicators)
        let score = aggregated?.score
        return MacroPanoramaPillar(
            id: section.id,
            nameZh: section.nameZh,
            score: score,
            level: score.map(MacroTemperatureLevel.from(score:)),
            validIndicatorCount: aggregated?.count ?? 0,
            totalIndicatorCount: section.indicators.count
        )
    }

    private static func catalogFallbackScore(from sections: [MacroIndicatorSection]) -> Double? {
        let allIndicators = sections.flatMap(\.indicators)
        return aggregateIndicators(allIndicators)?.score
    }

    private static func buildSummary(
        level: MacroTemperatureLevel?,
        scoredPillarCount: Int,
        hotCount: Int,
        neutralCount: Int,
        coldCount: Int
    ) -> String {
        if scoredPillarCount > 0 {
            if hotCount > 0 && coldCount > 0 {
                return L10n.fmt("当前 %lld 大宏观板块中，%lld 个处于偏热及以上区间、%lld 个偏冷，板块冷热呈现结构分化。", Int64(scoredPillarCount), Int64(hotCount), Int64(coldCount))
            }
            if hotCount > 0 {
                if neutralCount > 0 {
                    return L10n.fmt("当前 %lld 大宏观板块中，%lld 个处于偏热及以上区间、%lld 个中性，整体宏观热度偏高。", Int64(scoredPillarCount), Int64(hotCount), Int64(neutralCount))
                }
                return L10n.fmt("当前 %lld 大宏观板块均处于偏热及以上区间，整体宏观热度处于高位。", Int64(scoredPillarCount))
            }
            if coldCount > 0 {
                if neutralCount > 0 {
                    return L10n.fmt("当前 %lld 大宏观板块中，%lld 个处于偏冷及以下区间、%lld 个中性，整体宏观热度偏低。", Int64(scoredPillarCount), Int64(coldCount), Int64(neutralCount))
                }
                return L10n.fmt("当前 %lld 大宏观板块均处于偏冷及以下区间，整体宏观热度处于低位。", Int64(scoredPillarCount))
            }
            return L10n.fmt("当前 %lld 大宏观板块均处于中性区间，各项宏观指标分位整体平稳。", Int64(scoredPillarCount))
        }

        if let level {
            return L10n.fmt("宏观综合温度处于%@，各宏观板块指标分位同步完成后将展示分项热度。", level.defaultLabel)
        }

        return L10n.tr("宏观全景指标正在同步中，待数据就绪后自动计算综合温度与各板块分位。")
    }
}

enum MacroPanoramaThermometerGuideContent {
    static var title: String { L10n.tr("宏观全景温度计说明") }
    static var badgeText: String { L10n.tr("6 大板块 · 3 年分位 · 0°~100°") }
    static var methodology: String { L10n.tr("宏观全景温度计（0°~100°）优先与首页「长期 · 宏观背景」读数保持同源，综合刻画美债财政、利率水平、美元流动性、通胀增长、跨资产比价及资金情绪等长期宏观环境；若主温度接口尚未返回，则自动以各板块有效指标的折算分位均值作为无缝兜底。") }
    static var pillarRuleTitle: String { L10n.tr("6 大板块折算与联动说明") }
    static var pillarRuleNote: String { L10n.tr("每个板块基于旗下有效指标的近 3 年历史分位，按与黄金的同/反向统计关系折算均值（同向取原分位，反向取 100 − 分位；若板块全为中性指标则取原始均值）。点击任意板块条即可筛选下方对应指标卡片，再次点击取消筛选。") }

    static func levelDescription(for level: MacroTemperatureLevel) -> String {
        switch level {
        case .freezing:
            L10n.tr("多数宏观指标折算分位处于近 3 年极低区间，长期宏观支撑偏弱")
        case .cool:
            L10n.tr("宏观指标折算分位处于近 3 年偏低区间，整体宏观热度偏冷")
        case .neutral:
            L10n.tr("各宏观板块分位力量相对均衡，宏观环境处于中性常态")
        case .warm:
            L10n.tr("多项宏观指标折算分位走高，整体宏观热度偏强")
        case .hot:
            L10n.tr("多数宏观板块分位同步处于近 3 年高位，长期宏观驱动集中凸显")
        }
    }
}

// MARK: - 4. 美债财政压力表半圆弧视图与卡片

struct MacroTreasuryPressureGauge: View {
    let score: Double?
    let level: MacroTreasuryPressureLevel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: MacroTreasuryPressureGaugeGeometry {
        MacroTreasuryPressureGaugeGeometry(score: score)
    }

    private var accentColor: Color {
        level?.color ?? GoldTheme.textSecondary
    }

    var body: some View {
        let g = geometry

        ZStack {
            // 背景弧形轨道（严格内缩 lineWidth / 2，与彩色弧和刻度同圆心）
            Circle()
                .inset(by: g.strokeInset)
                .trim(from: 0, to: g.trackTrimEnd)
                .stroke(
                    GoldTheme.calendarCell,
                    style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(MacroTreasuryPressureGaugeGeometry.startAngleDegrees))

            // 内部主/次刻度线（压力表专属表盘特征）
            pressureTicks(geometry: g)

            // 压力渐变弧（冷灰蓝/绿 → 暗金 → 暖红，无首尾圆帽接缝）
            if g.hasScore {
                Circle()
                    .inset(by: g.strokeInset)
                    .trim(from: 0, to: g.activeTrimEnd)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: GoldTheme.tempFreezing, location: 0.00),
                                .init(color: GoldTheme.tempFreezing, location: 0.06),
                                .init(color: GoldTheme.tempCool, location: 0.20),
                                .init(color: GoldTheme.goldSoft, location: 0.32),
                                .init(color: GoldTheme.gold, location: 0.43),
                                .init(color: GoldTheme.tempWarm, location: 0.52),
                                .init(color: GoldTheme.tempHot, location: 0.64),
                                .init(color: GoldTheme.tempHot, location: 0.72),
                                .init(color: GoldTheme.tempFreezing, location: 0.97)
                            ]),
                            center: .center,
                            startAngle: .degrees(-20),
                            endAngle: .degrees(340)
                        ),
                        style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(MacroTreasuryPressureGaugeGeometry.startAngleDegrees))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: g.effectiveProgress)

                // 精准径向短指针（绕同一圆心旋转至 indicatorAngleDegrees，随弧线平滑扫动）
                Path { path in
                    path.move(to: CGPoint(x: g.center.x + g.pointerBaseRadius, y: g.center.y))
                    path.addLine(to: CGPoint(x: g.center.x + g.trackRadius - g.dotDiameter / 2, y: g.center.y))
                }
                .stroke(
                    accentColor.opacity(0.88),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(g.indicatorAngleDegrees))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: g.effectiveProgress)
                .allowsHitTesting(false)

                // 弧线终点指示光点（圆心严格落在 trackRadius 中线与彩色弧终点上）
                Circle()
                    .fill(GoldTheme.text)
                    .frame(width: g.dotDiameter, height: g.dotDiameter)
                    .overlay(Circle().stroke(accentColor, lineWidth: g.dotBorderWidth))
                    .position(g.indicatorCenter)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: g.effectiveProgress)
                    .allowsHitTesting(false)
            }

            // 中央分值与压力档位胶囊
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(g.hasScore ? String(format: "%.1f", g.clampedScore) : "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textFaint)
                }

                Text(level?.label ?? L10n.tr("待同步"))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .background(accentColor.opacity(0.14), in: GoldTheme.capsuleShape)
            }
            .position(x: g.center.x, y: g.center.y + 4)

            // 左右端点刻度标注
            Text(L10n.tr("0 低压"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(GoldTheme.textFaint)
                .position(x: g.startPoint.x + 14, y: g.startPoint.y + 18)

            Text(L10n.tr("100 极高"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(GoldTheme.textFaint)
                .position(x: g.endPoint.x - 16, y: g.endPoint.y + 18)
        }
        .frame(width: g.diameter, height: g.diameter)
        .frame(width: g.diameter, height: g.visibleHeight, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            g.hasScore
                ? L10n.fmt("美债财政压力指数 %@ 分，%@", String(format: "%.1f", g.clampedScore), level?.label ?? "")
                : L10n.tr("美债财政压力指数待同步")
        )
    }

    private func pressureTicks(geometry g: MacroTreasuryPressureGaugeGeometry) -> some View {
        ZStack {
            // 次刻度（每 5 分一格）
            Path { path in
                for value in stride(from: 0.0, through: 100.0, by: 5.0) {
                    if MacroTreasuryPressureGaugeGeometry.majorTickValues.contains(value) { continue }
                    let angle = g.angleDegrees(forScore: value)
                    path.move(to: g.point(atAngleDegrees: angle, radius: g.tickOuterRadius))
                    path.addLine(to: g.point(atAngleDegrees: angle, radius: g.tickOuterRadius - 3.5))
                }
            }
            .stroke(GoldTheme.textFaint.opacity(0.32), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            // 主刻度（0 / 25 / 50 / 75 / 100）
            Path { path in
                for value in MacroTreasuryPressureGaugeGeometry.majorTickValues {
                    let angle = g.angleDegrees(forScore: value)
                    path.move(to: g.point(atAngleDegrees: angle, radius: g.tickOuterRadius))
                    path.addLine(to: g.point(atAngleDegrees: angle, radius: g.tickInnerRadius))
                }
            }
            .stroke(GoldTheme.textFaint.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

struct MacroTreasuryPressureCard: View {
    let model: MacroTreasuryPressureModel
    let asOf: String
    let onShowGuide: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.needle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)

                        Text(L10n.tr("美债财政压力表"))
                            .font(.headline)
                            .foregroundStyle(GoldTheme.text)

                        Text(L10n.tr("财政信用压力"))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(model.level?.color ?? GoldTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                (model.level?.color ?? GoldTheme.textSecondary).opacity(0.14),
                                in: GoldTheme.capsuleShape
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(L10n.fmt("截至 %@ · 综合付息 / 赤字 / 债务率", MacroDateParser.displayDay(asOf)))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }

                Spacer(minLength: 4)

                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("查看美债财政压力表说明"))
                .accessibilityIdentifier("macro.treasury.pressureGuideButton")
            }

            MacroTreasuryPressureGauge(score: model.score, level: model.level)
                .padding(.top, 2)

            HStack(spacing: 8) {
                ForEach(model.drivers) { driver in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(driver.title)
                            .font(.system(size: 10.5))
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(driver.valueText)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(driver.hasValue ? GoldTheme.text : GoldTheme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(GoldTheme.background, in: GoldTheme.subCardShape)
                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "building.columns.fill")
                    .font(.caption)
                    .foregroundStyle(model.level?.color ?? GoldTheme.goldSoft)
                    .padding(.top, 2)
                Text(model.plainNote)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
        .goldCard(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macro.treasury.pressureCard")
    }
}

// MARK: - 5. 宏观全景温度计卡片与 6 大板块联动条

struct MacroPanoramaThermometerCard: View {
    let model: MacroPanoramaThermometerModel
    let selectedSectionID: String?
    let onToggleSection: (String) -> Void
    let onClearSelection: () -> Void
    let onShowGuide: () -> Void

    private let pillarColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            summaryRow

            if !model.pillars.isEmpty {
                Rectangle()
                    .fill(GoldTheme.cardStroke)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(L10n.tr("6 大宏观板块 · 近 3 年分位"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Spacer(minLength: 4)
                        if selectedSectionID != nil {
                            Button(action: onClearSelection) {
                                Text(L10n.tr("查看全部"))
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(GoldTheme.onGold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("macro.panorama.clearFilterButton")
                        } else {
                            Text(L10n.tr("点击板块筛选下方指标"))
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                        }
                    }

                    LazyVGrid(columns: pillarColumns, spacing: 8) {
                        ForEach(model.pillars) { pillar in
                            pillarTile(pillar)
                        }
                    }
                }
            }
        }
        .goldCard(padding: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macro.panorama.thermometerCard")
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Label(L10n.tr("宏观全景温度计"), systemImage: "globe.americas.fill")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.gold)

            Text(model.sourceBadgeText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(GoldTheme.goldSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            Button(action: onShowGuide) {
                Image(systemName: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("查看宏观全景温度计说明"))
            .accessibilityIdentifier("macro.panorama.guideButton")
        }
    }

    private var summaryRow: some View {
        let level = model.level
        let accent = level.map(MacroPresentation.temperatureColor(for:)) ?? GoldTheme.textSecondary

        return HStack(alignment: .center, spacing: 14) {
            if let score = model.score, let level {
                GoldTemperatureGauge(
                    score: score,
                    level: level,
                    levelLabel: level.defaultLabel,
                    compact: true
                )
            } else {
                placeholderCompactGauge
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(L10n.tr("综合读数"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(GoldTheme.calendarCell, in: GoldTheme.badgeShape)

                    Text(model.levelLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(accent.opacity(0.14), in: GoldTheme.capsuleShape)
                }

                Text(model.summaryText)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                if model.hotPillarCount + model.neutralPillarCount + model.coldPillarCount > 0 {
                    HStack(spacing: 8) {
                        pillarCountChip(L10n.fmt("偏热 %lld", Int64(model.hotPillarCount)), tint: GoldTheme.tempWarm)
                        pillarCountChip(L10n.fmt("中性 %lld", Int64(model.neutralPillarCount)), tint: GoldTheme.tempNeutral)
                        pillarCountChip(L10n.fmt("偏冷 %lld", Int64(model.coldPillarCount)), tint: GoldTheme.tempCool)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholderCompactGauge: some View {
        let g = GoldTemperatureGaugeGeometry(score: 0, compact: true)
        return ZStack {
            Circle()
                .inset(by: g.strokeInset)
                .trim(from: 0, to: g.trackTrimEnd)
                .stroke(
                    GoldTheme.calendarCell,
                    style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(g.startAngleDegrees))

            VStack(spacing: 2) {
                Text("—")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
                Text(L10n.tr("待同步"))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.textFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
            }
            .offset(y: 4)
        }
        .frame(width: g.size, height: g.size)
        .accessibilityLabel(L10n.tr("宏观全景温度待同步"))
    }

    private func pillarCountChip(_ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.textSecondary)
        }
    }

    private func pillarTile(_ pillar: MacroPanoramaPillar) -> some View {
        let isSelected = selectedSectionID == pillar.id
        let tint = pillar.level.map(MacroPresentation.temperatureColor(for:)) ?? GoldTheme.textFaint

        return Button {
            onToggleSection(pillar.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(pillar.localizedName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isSelected ? GoldTheme.goldSoft : GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 2)

                    Text(pillar.scoreText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: true, vertical: false)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        GoldTheme.capsuleShape.fill(GoldTheme.calendarCell)
                        if let score = pillar.score {
                            let fillWidth = max(6, proxy.size.width * (score / 100.0))
                            LinearGradient(
                                colors: [
                                    GoldTheme.tempFreezing,
                                    GoldTheme.tempCool,
                                    GoldTheme.tempNeutral,
                                    GoldTheme.tempWarm,
                                    GoldTheme.tempHot
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .mask(alignment: .leading) {
                                GoldTheme.capsuleShape
                                    .frame(width: fillWidth)
                            }
                        }
                    }
                }
                .frame(height: 5)

                HStack(spacing: 4) {
                    Text(pillar.shortStatusLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer(minLength: 2)
                    Text(isSelected ? L10n.tr("已筛选") : L10n.fmt("%lld 项", Int64(pillar.validIndicatorCount)))
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? GoldTheme.gold : GoldTheme.textFaint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? GoldTheme.gold.opacity(0.12) : GoldTheme.background,
                in: GoldTheme.subCardShape
            )
            .overlay(
                GoldTheme.subCardShape.strokeBorder(
                    isSelected ? GoldTheme.gold : GoldTheme.cardStroke,
                    lineWidth: isSelected ? 1.3 : 1
                )
            )
            .contentShape(GoldTheme.subCardShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("macro.panorama.pillar.\(pillar.id)")
    }
}

// MARK: - 6. 美债财政压力表说明 Sheet

struct MacroTreasuryPressureGuideSheet: View {
    var currentLevel: MacroTreasuryPressureLevel? = nil
    var disclaimer: String = MacroPresentation.defaultDisclaimer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Label(L10n.tr("计算方法论"), systemImage: "slider.horizontal.3")
                                .font(.subheadline.bold())
                                .foregroundStyle(GoldTheme.gold)
                            Spacer(minLength: 4)
                            Text(MacroTreasuryPressureGuideContent.badgeText)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                        }

                        Text(MacroTreasuryPressureGuideContent.methodology)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.text)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .goldCard(padding: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(MacroTreasuryPressureGuideContent.goldCreditRelationTitle, systemImage: "building.columns")
                            .font(.subheadline.bold())
                            .foregroundStyle(GoldTheme.gold)

                        Text(MacroTreasuryPressureGuideContent.goldCreditRelationNote)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .goldCard(padding: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(L10n.tr("压力五档区间"), systemImage: "gauge.with.needle")
                                .font(.subheadline.bold())
                                .foregroundStyle(GoldTheme.gold)
                            Spacer()
                            Text(L10n.tr("仅反映财政偿债与信用压力"))
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                        }

                        VStack(spacing: 7) {
                            ForEach(MacroTreasuryPressureLevel.allCases) { level in
                                pressureLevelRow(level)
                            }
                        }
                    }
                    .goldCard(padding: 14)

                    disclaimerFooter(disclaimer)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle(MacroTreasuryPressureGuideContent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(GoldTheme.gold)
                    .accessibilityIdentifier("macro.treasuryGuideSheet.doneButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .presentationDragIndicator(.visible)
    }

    private func pressureLevelRow(_ level: MacroTreasuryPressureLevel) -> some View {
        let tint = level.color
        let isCurrent = currentLevel == level

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(level.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)

                Text(level.rangeText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)

                Spacer(minLength: 4)

                if isCurrent {
                    Text(L10n.tr("当前区间"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.onGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint, in: GoldTheme.capsuleShape)
                }
            }

            Text(level.guideDescription)
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                isCurrent ? tint.opacity(0.45) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }
}

// MARK: - 7. 宏观全景温度计说明 Sheet

struct MacroPanoramaThermometerGuideSheet: View {
    var currentLevel: MacroTemperatureLevel? = nil
    var disclaimer: String = MacroPresentation.defaultDisclaimer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Label(L10n.tr("计算方法论"), systemImage: "slider.horizontal.3")
                                .font(.subheadline.bold())
                                .foregroundStyle(GoldTheme.gold)
                            Spacer(minLength: 4)
                            Text(MacroPanoramaThermometerGuideContent.badgeText)
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                        }

                        Text(MacroPanoramaThermometerGuideContent.methodology)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.text)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .goldCard(padding: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(MacroPanoramaThermometerGuideContent.pillarRuleTitle, systemImage: "square.grid.2x2")
                            .font(.subheadline.bold())
                            .foregroundStyle(GoldTheme.gold)

                        Text(MacroPanoramaThermometerGuideContent.pillarRuleNote)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .goldCard(padding: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(L10n.tr("宏观温度五档区间"), systemImage: "thermometer.medium")
                                .font(.subheadline.bold())
                                .foregroundStyle(GoldTheme.gold)
                            Spacer()
                            Text(L10n.tr("仅反映宏观指标历史分位"))
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                        }

                        VStack(spacing: 7) {
                            ForEach(MacroTemperatureGuideHelp.defaultGuide.levels) { item in
                                panoramaLevelRow(item)
                            }
                        }
                    }
                    .goldCard(padding: 14)

                    disclaimerFooter(disclaimer)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle(MacroPanoramaThermometerGuideContent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(GoldTheme.gold)
                    .accessibilityIdentifier("macro.panoramaGuideSheet.doneButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .presentationDragIndicator(.visible)
    }

    private func panoramaLevelRow(_ item: MacroTemperatureGuideLevel) -> some View {
        let tint = MacroPresentation.temperatureColor(for: item.level)
        let isCurrent = currentLevel == item.level

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(item.level.defaultLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)

                Text(item.range)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)

                Spacer(minLength: 4)

                if isCurrent {
                    Text(L10n.tr("当前区间"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.onGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint, in: GoldTheme.capsuleShape)
                }
            }

            Text(MacroPanoramaThermometerGuideContent.levelDescription(for: item.level))
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                isCurrent ? tint.opacity(0.45) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }
}

private func disclaimerFooter(_ text: String) -> some View {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolved = (MacroLocalization.isChinese && !trimmed.isEmpty) ? trimmed : MacroPresentation.defaultDisclaimer
    return HStack(alignment: .top, spacing: 6) {
        Image(systemName: "info.circle")
            .font(.caption2)
            .foregroundStyle(GoldTheme.textFaint)
            .padding(.top, 2)
        Text(resolved)
            .font(.caption2)
            .foregroundStyle(GoldTheme.textFaint)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
    .padding(.top, 2)
}
