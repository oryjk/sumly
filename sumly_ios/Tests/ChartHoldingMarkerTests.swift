import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite("ChartHoldingMarkerResolver")
struct ChartHoldingMarkerTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("同交易日精确命中当日收盘价（含同日不同时刻）")
    func exactTradingDayMatch() throws {
        let fri = noon(2026, 4, 10)
        let mon = noon(2026, 4, 13)
        let tue = noon(2026, 4, 14)
        let curve = [
            MarketChartPoint(date: fri, price: 610.0, granularity: .daily),
            MarketChartPoint(date: mon, price: 625.5, granularity: .daily),
            MarketChartPoint(date: tue, price: 632.0, granularity: .daily)
        ]

        let exactNoon = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: mon, in: curve, calendar: calendar))
        #expect(abs(exactNoon - 625.5) < 1e-9)

        let sameDayEvening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 13, hour: 20, minute: 30))!
        let eveningMatch = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: sameDayEvening, in: curve, calendar: calendar))
        #expect(abs(eveningMatch - 625.5) < 1e-9)
    }

    @Test("周末与休市日按前后交易日线性插值，区间外回退至最近交易日")
    func weekendInterpolationAndBoundaryFallback() throws {
        let fri = noon(2026, 4, 10) // 周五
        let sat = noon(2026, 4, 11) // 周六（1/3 处）
        let sun = noon(2026, 4, 12) // 周日（2/3 处）
        let mon = noon(2026, 4, 13) // 周一
        let thuBefore = noon(2026, 4, 9)
        let tueAfter = noon(2026, 4, 14)

        let curve = [
            MarketChartPoint(date: mon, price: 630.0, granularity: .daily), // 故意乱序验证排序健壮性
            MarketChartPoint(date: fri, price: 600.0, granularity: .daily)
        ]

        let satPrice = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: sat, in: curve, calendar: calendar))
        #expect(abs(satPrice - 610.0) < 1e-6)

        let sunPrice = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: sun, in: curve, calendar: calendar))
        #expect(abs(sunPrice - 620.0) < 1e-6)

        let beforePrice = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: thuBefore, in: curve, calendar: calendar))
        #expect(abs(beforePrice - 600.0) < 1e-9)

        let afterPrice = try #require(ChartHoldingMarkerResolver.marketAnchorPrice(for: tueAfter, in: curve, calendar: calendar))
        #expect(abs(afterPrice - 630.0) < 1e-9)
    }

    @Test("空曲线或仅含非法价格时安全返回 nil")
    func emptyOrInvalidCurveReturnsNil() {
        let target = noon(2026, 4, 13)
        #expect(ChartHoldingMarkerResolver.marketAnchorPrice(for: target, in: [], calendar: calendar) == nil)

        let invalidCurve = [
            MarketChartPoint(date: target, price: 0, granularity: .daily),
            MarketChartPoint(date: target, price: -10, granularity: .daily),
            MarketChartPoint(date: target, price: .nan, granularity: .daily),
            MarketChartPoint(date: target, price: .infinity, granularity: .daily)
        ]
        #expect(ChartHoldingMarkerResolver.marketAnchorPrice(for: target, in: invalidCurve, calendar: calendar) == nil)
    }

    @Test("线性与对数刻度坐标精确对齐且连接线方向一致")
    func linearAndLogarithmicScaleResolution() throws {
        let day1 = noon(2026, 4, 10)
        let day2 = noon(2026, 4, 13)
        let curve = [
            MarketChartPoint(date: day1, price: 600.0, granularity: .daily),
            MarketChartPoint(date: day2, price: 640.0, granularity: .daily)
        ]
        let markers = [
            // 买入价高于大盘（如含工费溢价）
            MarketHoldingOverlay.PurchaseMarker(date: day1, totalGrams: 10, averageUnitPrice: 625.0, count: 1),
            // 买入价低于大盘（如活动补贴）
            MarketHoldingOverlay.PurchaseMarker(date: day2, totalGrams: 5, averageUnitPrice: 620.0, count: 1)
        ]

        // 1. 线性刻度
        let linearDomain = ChartPriceScale.linear.domain(curve.map(\.price))
        let linearResolved = ChartHoldingMarkerResolver.resolve(
            markers: markers,
            curvePoints: curve,
            scale: .linear,
            domain: linearDomain,
            calendar: calendar
        )
        #expect(linearResolved.count == 2)
        #expect(abs(linearResolved[0].scaledCost - 625.0) < 1e-9)
        #expect(abs((linearResolved[0].scaledMarketAnchor ?? 0) - 600.0) < 1e-9)
        #expect(linearResolved[0].connectorRange == 600.0...625.0)
        #expect(linearResolved[1].connectorRange == 620.0...640.0)

        // 2. 对数刻度
        let logDomain = ChartPriceScale.logarithmic.domain(curve.map(\.price))
        let logResolved = ChartHoldingMarkerResolver.resolve(
            markers: markers,
            curvePoints: curve,
            scale: .logarithmic,
            domain: logDomain,
            calendar: calendar
        )
        #expect(logResolved.count == 2)
        let expectedCost0 = try #require(ChartPriceScale.logarithmic.value(625.0))
        let expectedAnchor0 = try #require(ChartPriceScale.logarithmic.value(600.0))
        #expect(abs(logResolved[0].scaledCost - expectedCost0) < 1e-12)
        #expect(abs((logResolved[0].scaledMarketAnchor ?? 0) - expectedAnchor0) < 1e-12)
        let logRange0 = try #require(logResolved[0].connectorRange)
        #expect(abs(logRange0.lowerBound - expectedAnchor0) < 1e-12)
        #expect(abs(logRange0.upperBound - expectedCost0) < 1e-12)

        let expectedCost1 = try #require(ChartPriceScale.logarithmic.value(620.0))
        let expectedAnchor1 = try #require(ChartPriceScale.logarithmic.value(640.0))
        let logRange1 = try #require(logResolved[1].connectorRange)
        #expect(abs(logRange1.lowerBound - expectedCost1) < 1e-12)
        #expect(abs(logRange1.upperBound - expectedAnchor1) < 1e-12)
    }

    @Test("红点越界跳过、锚点越界不画虚线、同价不画零长度虚线")
    func domainSafetyAndZeroDiffHandling() {
        let day = noon(2026, 4, 13)
        let curve = [MarketChartPoint(date: day, price: 620.0, granularity: .daily)]

        // 红点在 domain 之外（例如高溢价一口价金饰超出纵轴范围）-> 跳过
        let outOfDomainMarker = MarketHoldingOverlay.PurchaseMarker(date: day, totalGrams: 5, averageUnitPrice: 950.0, count: 1)
        let samePriceMarker = MarketHoldingOverlay.PurchaseMarker(date: day, totalGrams: 5, averageUnitPrice: 620.0, count: 1)
        let normalDomain = 580.0...660.0

        let resolved = ChartHoldingMarkerResolver.resolve(
            markers: [outOfDomainMarker, samePriceMarker],
            curvePoints: curve,
            scale: .linear,
            domain: normalDomain,
            calendar: calendar
        )
        #expect(resolved.count == 1)
        #expect(resolved[0].marker == samePriceMarker)
        #expect(resolved[0].connectorRange == nil)

        // 锚点在人为收窄的 domain 之外 -> 保留红点但安全跳过连接线与锚点
        let inNarrowDomainMarker = MarketHoldingOverlay.PurchaseMarker(date: day, totalGrams: 5, averageUnitPrice: 650.0, count: 1)
        let narrowDomain = 640.0...660.0
        let narrowResolved = ChartHoldingMarkerResolver.resolve(
            markers: [inNarrowDomainMarker],
            curvePoints: curve,
            scale: .linear,
            domain: narrowDomain,
            calendar: calendar
        )
        #expect(narrowResolved.count == 1)
        #expect(narrowResolved[0].scaledMarketAnchor == nil)
        #expect(narrowResolved[0].connectorRange == nil)
    }

    @Test("同日多笔聚合计算加权均价、单笔最低最高综合成本并保留逐笔明细")
    func multiPurchaseDailyAggregationAndItems() throws {
        let day = noon(2026, 4, 15)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 9, minute: 30))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 14, minute: 15))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 19, minute: 0))!
        let window = noon(2026, 4, 1)...noon(2026, 4, 30)

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let entries = [
            // 积存金 10g @ 610 (0工费) -> effective = 610
            HoldingsInsights.Entry(
                id: id2,
                assetType: "积存金",
                brand: "工商银行",
                channel: "银行",
                grams: 10,
                totalCost: 6100,
                unitPrice: 610,
                laborFee: 0,
                timestamp: afternoon,
                note: "定投",
                input: GoldReturnInput(grams: 10, unitPrice: 610)
            ),
            // 品牌金饰 5g @ 620 + 工费 250 = 3350 -> effective = 670
            HoldingsInsights.Entry(
                id: id3,
                assetType: "金饰",
                brand: "周大福",
                channel: "门店",
                grams: 5,
                totalCost: 3350,
                unitPrice: 620,
                laborFee: 250,
                timestamp: evening,
                note: "手链",
                input: GoldReturnInput(grams: 5, unitPrice: 620, laborFee: 250)
            ),
            // 投资金条 5g @ 620 + 工费 50 = 3150 -> effective = 630
            HoldingsInsights.Entry(
                id: id1,
                assetType: "金条",
                brand: "中国黄金",
                channel: "银行",
                grams: 5,
                totalCost: 3150,
                unitPrice: 620,
                laborFee: 50,
                timestamp: morning,
                note: "投资条",
                input: GoldReturnInput(grams: 5, unitPrice: 620, laborFee: 50)
            )
        ]

        let overlay = try #require(HoldingsInsights.marketOverlay(entries: entries, window: window, referencePrice: 640, calendar: calendar))
        #expect(overlay.markers.count == 1)

        let marker = overlay.markers[0]
        #expect(calendar.isDate(marker.date, inSameDayAs: day))
        #expect(marker.count == 3)
        #expect(abs(marker.totalGrams - 20.0) < 1e-9)
        // 总投入 = 6100 + 3350 + 3150 = 12600 -> 加权均价 630.0
        #expect(abs(marker.averageUnitPrice - 630.0) < 1e-9)
        #expect(abs(marker.minUnitCost - 610.0) < 1e-9)
        #expect(abs(marker.maxUnitCost - 670.0) < 1e-9)
        #expect(marker.items.count == 3)

        // 按 timestamp 升序排列：morning(id1) -> afternoon(id2) -> evening(id3)
        #expect(marker.items.map(\.id) == [id1, id2, id3])
        #expect(marker.items[0].resolvedAssetType == .bar)
        #expect(marker.items[0].laborFee == 50)
        #expect(abs(marker.items[0].effectiveUnitCost - 630.0) < 1e-9)
        #expect(marker.items[1].resolvedAssetType == .accumulation)
        #expect(marker.items[2].resolvedAssetType == .jewelry)
        #expect(marker.items[2].note == "手链")
        #expect(abs(marker.items[2].effectiveUnitCost - 670.0) < 1e-9)
    }

    @Test("单指滑动查价自动匹配同自然日与周末休市吸附且无冲突")
    func inspectionMatchingSameDayAndWeekendSnap() throws {
        let fri = noon(2026, 4, 10)
        let sat = noon(2026, 4, 11)
        let sun = noon(2026, 4, 12)
        let mon = noon(2026, 4, 13)
        let tue = noon(2026, 4, 14)

        let curve = [
            MarketChartPoint(date: fri, price: 610, granularity: .daily),
            MarketChartPoint(date: mon, price: 622, granularity: .daily),
            MarketChartPoint(date: tue, price: 630, granularity: .daily)
        ]
        let domain = 580.0...680.0

        // 1. 周六买入（距周五 1 天、距周一 2 天）-> 仅吸附周五；周二买入 -> 仅同日命中周二，不吸附周一
        let satMarker = MarketHoldingOverlay.PurchaseMarker(date: sat, totalGrams: 5, averageUnitPrice: 625, count: 1)
        let tueMarker = MarketHoldingOverlay.PurchaseMarker(date: tue, totalGrams: 10, averageUnitPrice: 635, count: 1)
        let resolved = ChartHoldingMarkerResolver.resolve(markers: [satMarker, tueMarker], curvePoints: curve, scale: .linear, domain: domain, calendar: calendar)
        #expect(resolved.count == 2)
        #expect(resolved[0].isInterpolatedMarketAnchor == true)
        #expect(resolved[1].isInterpolatedMarketAnchor == false)

        let friMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(selectedDate: fri, curvePoints: curve, resolvedMarkers: resolved, calendar: calendar))
        #expect(friMatch.resolved.marker.date == sat)
        #expect(friMatch.isSameDay == false)
        #expect(friMatch.dayDistance == 1)

        // 周一既无同日红点，也不是周六的最近交易日，且周二本身是交易日红点 -> 返回 nil，避免冲突
        let monMatch = ChartHoldingMarkerResolver.matchForInspection(selectedDate: mon, curvePoints: curve, resolvedMarkers: resolved, calendar: calendar)
        #expect(monMatch == nil)

        let tueMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(selectedDate: tue, curvePoints: curve, resolvedMarkers: resolved, calendar: calendar))
        #expect(tueMatch.resolved.marker.date == tue)
        #expect(tueMatch.isSameDay == true)
        #expect(tueMatch.dayDistance == 0)

        // 2. 周五作为当前区间最后一个交易日时，周日买入（相隔 2 天）自动吸附至周五
        let tailCurve = [MarketChartPoint(date: fri, price: 610, granularity: .daily)]
        let sunMarker = MarketHoldingOverlay.PurchaseMarker(date: sun, totalGrams: 3, averageUnitPrice: 618, count: 1)
        let tailResolved = ChartHoldingMarkerResolver.resolve(markers: [sunMarker], curvePoints: tailCurve, scale: .linear, domain: domain, calendar: calendar)
        let tailMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(selectedDate: fri, curvePoints: tailCurve, resolvedMarkers: tailResolved, calendar: calendar))
        #expect(tailMatch.resolved.marker.date == sun)
        #expect(tailMatch.isSameDay == false)
        #expect(tailMatch.dayDistance == 2)

        // 3. 相距 3 天以上的休市日不误吸附
        let farHoliday = noon(2026, 4, 17)
        let farCurve = [
            MarketChartPoint(date: noon(2026, 4, 14), price: 620, granularity: .daily),
            MarketChartPoint(date: noon(2026, 4, 21), price: 628, granularity: .daily)
        ]
        let farMarker = MarketHoldingOverlay.PurchaseMarker(date: farHoliday, totalGrams: 5, averageUnitPrice: 630, count: 1)
        let farResolved = ChartHoldingMarkerResolver.resolve(markers: [farMarker], curvePoints: farCurve, scale: .linear, domain: domain, calendar: calendar)
        #expect(ChartHoldingMarkerResolver.matchForInspection(selectedDate: noon(2026, 4, 14), curvePoints: farCurve, resolvedMarkers: farResolved, calendar: calendar) == nil)
    }

    @Test("44pt 隐形命中热区判定：精确命中、多点取最近、超出 22pt 半径不误触发")
    func hitTestFortyFourPointTarget() throws {
        let d1 = noon(2026, 4, 10)
        let d2 = noon(2026, 4, 15)
        let m1 = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: .init(date: d1, totalGrams: 5, averageUnitPrice: 620, count: 1),
            scaledCost: 620,
            marketAnchorPrice: 610,
            scaledMarketAnchor: 610
        )
        let m2 = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: .init(date: d2, totalGrams: 10, averageUnitPrice: 635, count: 2),
            scaledCost: 635,
            marketAnchorPrice: 628,
            scaledMarketAnchor: 628
        )
        let screenPoints = [
            ChartHoldingMarkerResolver.MarkerScreenPoint(resolved: m1, point: CGPoint(x: 100, y: 120)),
            ChartHoldingMarkerResolver.MarkerScreenPoint(resolved: m2, point: CGPoint(x: 130, y: 120))
        ]

        // 1. 精确命中红点中心
        let exact = try #require(ChartHoldingMarkerResolver.hitTest(tapPoint: CGPoint(x: 100, y: 120), markerPoints: screenPoints))
        #expect(exact.id == d1)

        // 2. 边界距离内（dx=15, dy=16 -> dist=21.93 <= 22）仍可命中
        let edgeInside = try #require(ChartHoldingMarkerResolver.hitTest(tapPoint: CGPoint(x: 85, y: 104), markerPoints: screenPoints))
        #expect(edgeInside.id == d1)

        // 3. 两点热区重叠区域内取最近红点（x=118 距 m1=18pt，距 m2=12pt -> 命中 m2）
        let closer = try #require(ChartHoldingMarkerResolver.hitTest(tapPoint: CGPoint(x: 118, y: 120), markerPoints: screenPoints))
        #expect(closer.id == d2)

        // 4. 超出 22pt 半径（dx=16, dy=16 -> dist=22.63 > 22）不误触发
        #expect(ChartHoldingMarkerResolver.hitTest(tapPoint: CGPoint(x: 84, y: 104), markerPoints: screenPoints) == nil)
        #expect(ChartHoldingMarkerResolver.hitTest(tapPoint: CGPoint(x: 100, y: 142.1), markerPoints: screenPoints) == nil)
    }

    @Test("多笔微标、隐私脱敏与零投顾违规词校验")
    func badgePrivacyRedactionAndZeroAdvisoryWording() throws {
        // 1. 微标文本边界
        #expect(ChartPurchaseMarkerPresentation.badgeText(for: 1) == nil)
        #expect(ChartPurchaseMarkerPresentation.badgeText(for: 2) == "2")
        #expect(ChartPurchaseMarkerPresentation.badgeText(for: 9) == "9")
        #expect(ChartPurchaseMarkerPresentation.badgeText(for: 10) == "9+")

        // 2. 隐私脱敏校验
        let day = noon(2026, 4, 15)
        let item1 = MarketHoldingOverlay.PurchaseItem(
            id: UUID(), assetType: "金饰", brand: "周大福", grams: 12.5,
            unitPrice: 640, effectiveUnitCost: 688, totalCost: 8600, laborFee: 600, timestamp: day, note: "纪念"
        )
        let item2 = MarketHoldingOverlay.PurchaseItem(
            id: UUID(), assetType: "金条", brand: "中国黄金", grams: 20,
            unitPrice: 625, effectiveUnitCost: 635, totalCost: 12700, laborFee: 200, timestamp: day, note: ""
        )
        let multiMarker = MarketHoldingOverlay.PurchaseMarker(
            date: day, totalGrams: 32.5, averageUnitPrice: 655.38, count: 2, items: [item1, item2]
        )
        let resolvedMulti = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: multiMarker, scaledCost: 655.38, marketAnchorPrice: 620.0, scaledMarketAnchor: 620.0
        )
        let match = ChartHoldingMarkerResolver.MatchedInspectionMarker(resolved: resolvedMulti, isSameDay: true, dayDistance: 0)
        let selectedPoint = MarketChartPoint(date: day, price: 620.0, granularity: .daily)

        let redactedTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: match, selectedPoint: selectedPoint, hideAmounts: true, calendar: calendar
        )
        #expect(redactedTooltip.headline.contains("••••"))
        #expect(!redactedTooltip.headline.contains("32.5"))
        #expect(redactedTooltip.footerHint == "轻点红点查看明细")

        let visibleTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: match, selectedPoint: selectedPoint, hideAmounts: false, calendar: calendar
        )
        #expect(visibleTooltip.headline.contains("买入 2 笔"))
        #expect(visibleTooltip.headline.contains("32.5g"))
        #expect(visibleTooltip.secondaryMetric?.contains("635.00") == true)
        #expect(visibleTooltip.secondaryMetric?.contains("688.00") == true)

        #expect(ChartPurchaseMarkerPresentation.totalCostText(8600, hideAmounts: true) == "••••")
        #expect(ChartPurchaseMarkerPresentation.laborFeeTagText(600, hideAmounts: true) == "含工费 ••••")
        #expect(ChartPurchaseMarkerPresentation.laborFeeTagText(0, hideAmounts: false) == nil)

        // 3. 零投顾违规词校验
        let spreadPremium = try #require(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 656.10, marketAnchor: 620.0))
        let spreadDiscount = try #require(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 615.80, marketAnchor: 620.0))
        let spreadNeutral = try #require(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620.0, marketAnchor: 620.0))
        let spreadInterpolatedPremium = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 656.10, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        let spreadInterpolatedDiscount = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 615.80, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        let spreadInterpolatedNeutral = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620.0, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        #expect(spreadPremium.capsuleText == "较当日大盘多花 ¥36.10/g（贵 5.82%）")
        #expect(spreadDiscount.capsuleText == "较当日大盘省 ¥4.20/g（省 0.68%）")

        let allCopy = [
            ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: false),
            ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: true),
            spreadPremium.capsuleText,
            spreadPremium.compactText,
            spreadDiscount.capsuleText,
            spreadDiscount.compactText,
            spreadNeutral.capsuleText,
            spreadNeutral.compactText,
            spreadInterpolatedPremium.capsuleText,
            spreadInterpolatedDiscount.capsuleText,
            spreadInterpolatedNeutral.capsuleText,
            visibleTooltip.headline,
            visibleTooltip.primaryMetric,
            visibleTooltip.secondaryMetric ?? "",
            visibleTooltip.footerHint ?? ""
        ].joined(separator: " ")

        let forbiddenAdvisoryTerms = [
            "建议", "推荐", "抄底", "逢低", "加仓", "减仓", "追高",
            "止盈", "止损", "看涨", "看跌", "买入时机", "投资机会", "必涨", "目标价"
        ]
        for term in forbiddenAdvisoryTerms {
            #expect(!allCopy.contains(term), "文案不得包含投顾违规词：\(term)")
        }
    }

    @Test("买入价与大盘差额语义、红绿配色、图标、正常日与休市插值文案及滑查浮窗断言")
    func spreadSentimentWordingAndInspectionTooltipSemantics() throws {
        // 1. 买贵了（unitCost > marketAnchor）-> unfavorable / 绿色 GoldTheme.down / arrow.down.right
        let unfavorableDaily = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 656.10, marketAnchor: 620.0)
        )
        #expect(unfavorableDaily.isPremium == true)
        #expect(unfavorableDaily.isDiscount == false)
        #expect(unfavorableDaily.sentiment == .unfavorable)
        #expect(unfavorableDaily.sentiment.color == GoldTheme.down)
        #expect(unfavorableDaily.sentiment.symbolName == "arrow.down.right")
        #expect(unfavorableDaily.capsuleText == "较当日大盘多花 ¥36.10/g（贵 5.82%）")
        #expect(unfavorableDaily.compactText == "多花 ¥36.10")

        let unfavorableInterpolated = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 656.10, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        #expect(unfavorableInterpolated.sentiment == .unfavorable)
        #expect(unfavorableInterpolated.capsuleText == "较临近交易日多花 ¥36.10/g（贵 5.82%）")
        #expect(unfavorableInterpolated.compactText == "多花 ¥36.10")

        // 2. 买便宜了（unitCost < marketAnchor）-> favorable / 红色 GoldTheme.up / arrow.up.right
        let favorableDaily = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 615.80, marketAnchor: 620.0)
        )
        #expect(favorableDaily.isPremium == false)
        #expect(favorableDaily.isDiscount == true)
        #expect(favorableDaily.sentiment == .favorable)
        #expect(favorableDaily.sentiment.color == GoldTheme.up)
        #expect(favorableDaily.sentiment.symbolName == "arrow.up.right")
        #expect(favorableDaily.capsuleText == "较当日大盘省 ¥4.20/g（省 0.68%）")
        #expect(favorableDaily.compactText == "省 ¥4.20")

        let favorableInterpolated = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 615.80, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        #expect(favorableInterpolated.sentiment == .favorable)
        #expect(favorableInterpolated.capsuleText == "较临近交易日省 ¥4.20/g（省 0.68%）")
        #expect(favorableInterpolated.compactText == "省 ¥4.20")

        // 3. 持平（abs(diff) < 0.005）-> neutral / 次要灰 GoldTheme.textSecondary / equal
        let neutralExact = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620.0, marketAnchor: 620.0)
        )
        #expect(neutralExact.diff == 0)
        #expect(neutralExact.percent == 0)
        #expect(neutralExact.isPremium == false)
        #expect(neutralExact.isDiscount == false)
        #expect(neutralExact.sentiment == .neutral)
        #expect(neutralExact.sentiment.color == GoldTheme.textSecondary)
        #expect(neutralExact.sentiment.symbolName == "equal")
        #expect(neutralExact.capsuleText == "与当日大盘持平 (¥0.00/g)")
        #expect(neutralExact.compactText == "与大盘持平")

        let neutralThresholdPos = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620.004, marketAnchor: 620.0)
        )
        let neutralThresholdNeg = try #require(
            ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 619.996, marketAnchor: 620.0, isInterpolatedMarketAnchor: true)
        )
        #expect(neutralThresholdPos.sentiment == .neutral)
        #expect(neutralThresholdNeg.sentiment == .neutral)
        #expect(neutralThresholdNeg.capsuleText == "与临近交易日持平 (¥0.00/g)")
        #expect(neutralThresholdNeg.compactText == "与大盘持平")

        // 4. 非法输入安全返回 nil
        #expect(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620, marketAnchor: nil) == nil)
        #expect(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620, marketAnchor: 0) == nil)
        #expect(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 620, marketAnchor: -10) == nil)
        #expect(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: 0, marketAnchor: 620) == nil)
        #expect(ChartPurchaseMarkerPresentation.spreadMetric(unitCost: .nan, marketAnchor: 620) == nil)

        // 5. inspectionTooltip 输出断言：正常交易日多花 / 正常交易日省钱 / 休市插值日吸附 / 持平 / 4 位单价
        let fri = noon(2026, 4, 10)
        let sat = noon(2026, 4, 11)
        let selectedFri = MarketChartPoint(date: fri, price: 1020.0, granularity: .daily)

        // 5a. 正常交易日 4 位单价买贵
        let premiumItem = MarketHoldingOverlay.PurchaseItem(
            id: UUID(), assetType: "金饰", brand: "周大福", grams: 10,
            unitPrice: 1050.0, effectiveUnitCost: 1085.50, totalCost: 10855.0, laborFee: 355.0, timestamp: fri, note: ""
        )
        let premiumMarker = MarketHoldingOverlay.PurchaseMarker(
            date: fri, totalGrams: 10, averageUnitPrice: 1085.50, count: 1, items: [premiumItem]
        )
        let premiumResolved = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: premiumMarker, scaledCost: 1085.50, marketAnchorPrice: 1020.0, scaledMarketAnchor: 1020.0,
            isInterpolatedMarketAnchor: false
        )
        let premiumTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: .init(resolved: premiumResolved, isSameDay: true, dayDistance: 0),
            selectedPoint: selectedFri,
            hideAmounts: false,
            calendar: calendar
        )
        #expect(premiumTooltip.dateBadge == nil)
        #expect(premiumTooltip.primaryMetric == "买入 ¥1085.50/g")
        let premiumSpread = try #require(premiumTooltip.spread)
        #expect(premiumSpread.sentiment == .unfavorable)
        #expect(premiumSpread.sentiment.color == GoldTheme.down)
        #expect(premiumSpread.compactText == "多花 ¥65.50")
        #expect(premiumSpread.capsuleText == "较当日大盘多花 ¥65.50/g（贵 6.42%）")

        // 5b. 正常交易日买便宜
        let discountItem = MarketHoldingOverlay.PurchaseItem(
            id: UUID(), assetType: "积存金", brand: "工商银行", grams: 15,
            unitPrice: 1008.20, effectiveUnitCost: 1008.20, totalCost: 15123.0, laborFee: 0, timestamp: fri, note: ""
        )
        let discountMarker = MarketHoldingOverlay.PurchaseMarker(
            date: fri, totalGrams: 15, averageUnitPrice: 1008.20, count: 1, items: [discountItem]
        )
        let discountResolved = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: discountMarker, scaledCost: 1008.20, marketAnchorPrice: 1020.0, scaledMarketAnchor: 1020.0,
            isInterpolatedMarketAnchor: false
        )
        let discountTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: .init(resolved: discountResolved, isSameDay: true, dayDistance: 0),
            selectedPoint: selectedFri,
            hideAmounts: false,
            calendar: calendar
        )
        let discountSpread = try #require(discountTooltip.spread)
        #expect(discountSpread.sentiment == .favorable)
        #expect(discountSpread.sentiment.color == GoldTheme.up)
        #expect(discountSpread.compactText == "省 ¥11.80")
        #expect(discountSpread.capsuleText == "较当日大盘省 ¥11.80/g（省 1.16%）")

        // 5c. 休市插值日吸附（周六买入吸附周五）
        let weekendMarker = MarketHoldingOverlay.PurchaseMarker(
            date: sat, totalGrams: 8, averageUnitPrice: 1032.0, count: 1
        )
        let weekendResolved = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: weekendMarker, scaledCost: 1032.0, marketAnchorPrice: 1020.0, scaledMarketAnchor: 1020.0,
            isInterpolatedMarketAnchor: true
        )
        let weekendTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: .init(resolved: weekendResolved, isSameDay: false, dayDistance: 1),
            selectedPoint: selectedFri,
            hideAmounts: false,
            calendar: calendar
        )
        #expect(weekendTooltip.dateBadge == "04/11 买入 · 休市参考")
        let weekendSpread = try #require(weekendTooltip.spread)
        #expect(weekendSpread.sentiment == .unfavorable)
        #expect(weekendSpread.compactText == "多花 ¥12.00")
        #expect(weekendSpread.capsuleText == "较临近交易日多花 ¥12.00/g（贵 1.18%）")

        // 5d. 持平场景
        let flatMarker = MarketHoldingOverlay.PurchaseMarker(
            date: fri, totalGrams: 5, averageUnitPrice: 1020.0, count: 1
        )
        let flatResolved = ChartHoldingMarkerResolver.ResolvedMarker(
            marker: flatMarker, scaledCost: 1020.0, marketAnchorPrice: 1020.0, scaledMarketAnchor: 1020.0,
            isInterpolatedMarketAnchor: false
        )
        let flatTooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: .init(resolved: flatResolved, isSameDay: true, dayDistance: 0),
            selectedPoint: selectedFri,
            hideAmounts: false,
            calendar: calendar
        )
        let flatSpread = try #require(flatTooltip.spread)
        #expect(flatSpread.sentiment == .neutral)
        #expect(flatSpread.sentiment.color == GoldTheme.textSecondary)
        #expect(flatSpread.compactText == "与大盘持平")
        #expect(flatSpread.capsuleText == "与当日大盘持平 (¥0.00/g)")
    }

    @Test("休市/未收盘买入挂靠最右端、7天长假边界、历史回拖不误挂靠与全量 overlay")
    func pendingCloseTrailingAnchorAndHolidayBounds() throws {
        let wed = noon(2026, 11, 18)
        let thu = noon(2026, 11, 19)
        let fri = noon(2026, 11, 20)
        let sat = noon(2026, 11, 21)
        let sun = noon(2026, 11, 22)
        let day7 = noon(2026, 11, 27) // 距周五 11/20 正好 7 天
        let day8 = noon(2026, 11, 28) // 距周五 11/20 共 8 天（超出 7 天上限）
        let olderDay = noon(2026, 10, 15)

        let curve = [
            MarketChartPoint(date: wed, price: 790.00, granularity: .daily),
            MarketChartPoint(date: thu, price: 778.20, granularity: .daily),
            MarketChartPoint(date: fri, price: 764.55, granularity: .daily)
        ]
        let liveXDomain = noon(2026, 11, 1)...sat
        let domain = 730.0...830.0

        // 1. 周日 11/22 买入 ¥755.01 -> 临时挂靠周五 11/20，保留真实 marker.date 与 id
        let sunMarker = MarketHoldingOverlay.PurchaseMarker(date: sun, totalGrams: 10, averageUnitPrice: 755.01, count: 1)
        let resolvedSun = ChartHoldingMarkerResolver.resolve(
            markers: [sunMarker],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: liveXDomain,
            calendar: calendar
        )
        #expect(resolvedSun.count == 1)
        let anchored = try #require(resolvedSun.first)
        #expect(anchored.id == sun)
        #expect(anchored.marker.date == sun)
        #expect(anchored.plotDate == fri)
        #expect(anchored.isPendingCloseAnchor == true)
        #expect(anchored.isInterpolatedMarketAnchor == true)
        #expect(abs((anchored.marketAnchorPrice ?? 0) - 764.55) < 1e-9)
        #expect(anchored.connectorRange == 755.01...764.55)

        // 2. 7 天长假边界：+7 天允许挂靠，+8 天不挂靠
        let holiday7 = MarketHoldingOverlay.PurchaseMarker(date: day7, totalGrams: 5, averageUnitPrice: 770.0, count: 1)
        let holiday8 = MarketHoldingOverlay.PurchaseMarker(date: day8, totalGrams: 5, averageUnitPrice: 772.0, count: 1)
        let resolvedHoliday = ChartHoldingMarkerResolver.resolve(
            markers: [holiday7, holiday8],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: liveXDomain,
            calendar: calendar
        )
        #expect(resolvedHoliday.count == 1)
        #expect(resolvedHoliday[0].marker.date == day7)
        #expect(resolvedHoliday[0].plotDate == fri)
        #expect(resolvedHoliday[0].isPendingCloseAnchor == true)

        // 3. 历史回拖视口（不包含 lastCurveDate 周五 11/20）-> 不误挂靠周日买入，且过滤掉视口外历史点
        let pannedXDomain = noon(2026, 11, 1)...thu
        let olderMarker = MarketHoldingOverlay.PurchaseMarker(date: olderDay, totalGrams: 5, averageUnitPrice: 760.0, count: 1)
        let wedMarker = MarketHoldingOverlay.PurchaseMarker(date: wed, totalGrams: 5, averageUnitPrice: 785.0, count: 1)
        let resolvedPanned = ChartHoldingMarkerResolver.resolve(
            markers: [olderMarker, wedMarker, sunMarker],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: pannedXDomain,
            calendar: calendar
        )
        #expect(resolvedPanned.count == 1)
        #expect(resolvedPanned[0].marker.date == wed)
        #expect(resolvedPanned[0].plotDate == wed)
        #expect(resolvedPanned[0].isPendingCloseAnchor == false)

        // 4. HoldingsInsights.marketOverlay(window: nil) 保留今日未收盘与视口外历史买入，确保端到端不提前丢弃
        let entries = [
            HoldingsInsights.Entry(
                assetType: "积存金", brand: "工商银行", channel: "银行",
                grams: 10, totalCost: 7550.10, unitPrice: 755.01, timestamp: sun,
                input: GoldReturnInput(grams: 10, unitPrice: 755.01)
            ),
            HoldingsInsights.Entry(
                assetType: "金条", brand: "中国黄金", channel: "银行",
                grams: 5, totalCost: 3800.0, unitPrice: 760.0, timestamp: olderDay,
                input: GoldReturnInput(grams: 5, unitPrice: 760.0)
            )
        ]
        let allOverlay = try #require(HoldingsInsights.marketOverlay(entries: entries, window: nil, referencePrice: 764.55, calendar: calendar))
        #expect(allOverlay.markers.count == 2)
        #expect(allOverlay.markers.contains { calendar.isDate($0.date, inSameDayAs: sun) })
        #expect(allOverlay.markers.contains { calendar.isDate($0.date, inSameDayAs: olderDay) })
    }

    @Test("Y 轴 ±25% 合理扩展（纳入 755.01、过滤 1800 极端离群）与视口外笔数统计")
    func expandedPriceDomainAndOutOfViewportCount() throws {
        let wed = noon(2026, 11, 18)
        let thu = noon(2026, 11, 19)
        let fri = noon(2026, 11, 20)
        let sat = noon(2026, 11, 21)
        let sun = noon(2026, 11, 22)
        let oct = noon(2026, 10, 10)

        let curve = [
            MarketChartPoint(date: wed, price: 815.00, granularity: .daily),
            MarketChartPoint(date: thu, price: 785.00, granularity: .daily),
            MarketChartPoint(date: fri, price: 764.55, granularity: .daily)
        ]
        let xDomain = noon(2026, 11, 1)...sat
        let baseLinear = ChartPriceScale.linear.domain(curve.map(\.price))

        // 1. ¥755.01 仅低于最低价 ¥764.55 约 1.25%，落在 ±25% 内 -> 平滑扩展纵轴并成功解析红点
        let nearLowMarker = MarketHoldingOverlay.PurchaseMarker(date: sun, totalGrams: 10, averageUnitPrice: 755.01, count: 1)
        let expandedLinear = ChartHoldingMarkerResolver.expandedPriceDomain(
            curvePoints: curve,
            markers: [nearLowMarker],
            xDomain: xDomain,
            scale: .linear,
            calendar: calendar
        )
        #expect(expandedLinear.lowerBound < baseLinear.lowerBound)
        #expect(expandedLinear.contains(755.01))

        let resolvedNearLow = ChartHoldingMarkerResolver.resolve(
            markers: [nearLowMarker],
            curvePoints: curve,
            scale: .linear,
            domain: expandedLinear,
            xDomain: xDomain,
            calendar: calendar
        )
        #expect(resolvedNearLow.count == 1)
        #expect(resolvedNearLow[0].isPendingCloseAnchor == true)

        // 对数刻度同样平滑纳入 ¥755.01
        let expandedLog = ChartHoldingMarkerResolver.expandedPriceDomain(
            curvePoints: curve,
            markers: [nearLowMarker],
            xDomain: xDomain,
            scale: .logarithmic,
            calendar: calendar
        )
        let log755 = try #require(ChartPriceScale.logarithmic.value(755.01))
        #expect(expandedLog.contains(log755))

        // 2. 极端高溢价离群点 ¥1800（超出 curveMax +25%）与极端低价 ¥400 -> 不拉宽纵轴，不压扁大盘曲线
        let outlierHigh = MarketHoldingOverlay.PurchaseMarker(date: thu, totalGrams: 2, averageUnitPrice: 1800.0, count: 1)
        let outlierLow = MarketHoldingOverlay.PurchaseMarker(date: wed, totalGrams: 2, averageUnitPrice: 400.0, count: 1)
        let domainWithOutliers = ChartHoldingMarkerResolver.expandedPriceDomain(
            curvePoints: curve,
            markers: [outlierHigh, outlierLow],
            xDomain: xDomain,
            scale: .linear,
            calendar: calendar
        )
        #expect(domainWithOutliers == baseLinear)

        // 3. 视口外历史买入不参与 Y 轴扩展，并计入 outOfViewportPurchaseCount（按 marker.count 求和）
        let outMarker1 = MarketHoldingOverlay.PurchaseMarker(date: oct, totalGrams: 5, averageUnitPrice: 710.0, count: 2)
        let outMarker2 = MarketHoldingOverlay.PurchaseMarker(date: noon(2026, 9, 15), totalGrams: 3, averageUnitPrice: 720.0, count: 1)
        let domainWithOutOfView = ChartHoldingMarkerResolver.expandedPriceDomain(
            curvePoints: curve,
            markers: [outMarker1, outMarker2],
            xDomain: xDomain,
            scale: .linear,
            calendar: calendar
        )
        #expect(domainWithOutOfView == baseLinear)

        let resolvedNone = ChartHoldingMarkerResolver.resolve(
            markers: [outMarker1, outMarker2],
            curvePoints: curve,
            scale: .linear,
            domain: domainWithOutOfView,
            xDomain: xDomain,
            calendar: calendar
        )
        #expect(resolvedNone.isEmpty)
        #expect(ChartHoldingMarkerResolver.outOfViewportPurchaseCount(allMarkers: [outMarker1, outMarker2], resolvedMarkers: resolvedNone) == 3)

        // 混合场景：1 笔在视口内，3 笔在视口外
        let allMixed = [outMarker1, outMarker2, nearLowMarker]
        let resolvedMixed = ChartHoldingMarkerResolver.resolve(
            markers: allMixed,
            curvePoints: curve,
            scale: .linear,
            domain: expandedLinear,
            xDomain: xDomain,
            calendar: calendar
        )
        #expect(resolvedMixed.count == 1)
        #expect(ChartHoldingMarkerResolver.outOfViewportPurchaseCount(allMarkers: allMixed, resolvedMarkers: resolvedMixed) == 3)
        #expect(ChartHoldingMarkerResolver.outOfViewportPurchaseCount(allMarkers: [nearLowMarker], resolvedMarkers: resolvedNearLow) == 0)
    }

    @Test("待收盘挂靠红点滑查命中（含 7 天长假）、抽屉文案与零投顾合规断言")
    func pendingCloseInspectionAndSheetWordingCompliance() throws {
        let thu = noon(2026, 11, 19)
        let fri = noon(2026, 11, 20)
        let sat = noon(2026, 11, 21)
        let sun = noon(2026, 11, 22)
        let holidayDay7 = noon(2026, 11, 27)

        let curve = [
            MarketChartPoint(date: thu, price: 778.20, granularity: .daily),
            MarketChartPoint(date: fri, price: 764.55, granularity: .daily)
        ]
        let xDomain = noon(2026, 11, 1)...sat
        let domain = 730.0...820.0

        // 1. 滑动查价到周五 11/20 -> 命中周日 11/22 待收盘挂靠红点；滑到周四 11/19 不误命中
        let sunItem = MarketHoldingOverlay.PurchaseItem(
            id: UUID(), assetType: "积存金", brand: "工商银行", grams: 10,
            unitPrice: 755.01, effectiveUnitCost: 755.01, totalCost: 7550.10, laborFee: 0, timestamp: sun, note: "周末定投"
        )
        let sunMarker = MarketHoldingOverlay.PurchaseMarker(
            date: sun, totalGrams: 10, averageUnitPrice: 755.01, count: 1, items: [sunItem]
        )
        let resolvedSun = ChartHoldingMarkerResolver.resolve(
            markers: [sunMarker],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: xDomain,
            calendar: calendar
        )
        let friMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(
            selectedDate: fri,
            curvePoints: curve,
            resolvedMarkers: resolvedSun,
            calendar: calendar
        ))
        #expect(friMatch.resolved.marker.date == sun)
        #expect(friMatch.resolved.plotDate == fri)
        #expect(friMatch.resolved.isPendingCloseAnchor == true)
        #expect(friMatch.isSameDay == false)
        #expect(friMatch.dayDistance == 2)
        #expect(ChartHoldingMarkerResolver.matchForInspection(
            selectedDate: thu,
            curvePoints: curve,
            resolvedMarkers: resolvedSun,
            calendar: calendar
        ) == nil)

        // 2. 7 天长假待收盘挂靠红点同样在 lastCurveDate 命中（不受 2 天距离限制）
        let holidayMarker = MarketHoldingOverlay.PurchaseMarker(date: holidayDay7, totalGrams: 5, averageUnitPrice: 772.0, count: 1)
        let resolvedHoliday = ChartHoldingMarkerResolver.resolve(
            markers: [holidayMarker],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: xDomain,
            calendar: calendar
        )
        let holidayMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(
            selectedDate: fri,
            curvePoints: curve,
            resolvedMarkers: resolvedHoliday,
            calendar: calendar
        ))
        #expect(holidayMatch.resolved.marker.date == holidayDay7)
        #expect(holidayMatch.dayDistance == 7)

        // 3. 若周五 11/20 本身有精确同日买入点，优先命中同日点
        let friMarker = MarketHoldingOverlay.PurchaseMarker(date: fri, totalGrams: 5, averageUnitPrice: 766.0, count: 1)
        let resolvedBoth = ChartHoldingMarkerResolver.resolve(
            markers: [friMarker, sunMarker],
            curvePoints: curve,
            scale: .linear,
            domain: domain,
            xDomain: xDomain,
            calendar: calendar
        )
        let exactMatch = try #require(ChartHoldingMarkerResolver.matchForInspection(
            selectedDate: fri,
            curvePoints: curve,
            resolvedMarkers: resolvedBoth,
            calendar: calendar
        ))
        #expect(exactMatch.isSameDay == true)
        #expect(exactMatch.resolved.marker.date == fri)

        // 4. 浮窗与半屏明细抽屉待收盘文案校验
        let tooltip = ChartPurchaseMarkerPresentation.inspectionTooltip(
            match: friMatch,
            selectedPoint: MarketChartPoint(date: fri, price: 764.55, granularity: .daily),
            hideAmounts: false,
            calendar: calendar
        )
        #expect(tooltip.dateBadge == "11/22 买入 · 待收盘参考")
        let tooltipSpread = try #require(tooltip.spread)
        #expect(tooltipSpread.capsuleText == "较最近收盘省 ¥9.54/g（省 1.25%）")
        #expect(tooltipSpread.sentiment == .favorable)

        let statusBadge = ChartPurchaseMarkerPresentation.statusBadgeText(isInterpolatedMarketAnchor: true, isPendingCloseAnchor: true)
        let refTitle = ChartPurchaseMarkerPresentation.referencePriceTitle(isInterpolatedMarketAnchor: true, isPendingCloseAnchor: true)
        let explanation = ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: true, isPendingCloseAnchor: true)
        #expect(statusBadge == "休市/待收盘 · 参考最近收盘")
        #expect(refTitle == "最近收盘参考价")
        #expect(explanation == "买入日尚未产生收盘日线（休市或盘中），红点暂挂靠于最近交易日末端并参考该日收盘价；次交易日收盘后自动归位。")
        #expect(ChartPurchaseMarkerPresentation.fullDateText(sun, calendar: calendar) == "2026年11月22日")

        let pendingPremium = try #require(ChartPurchaseMarkerPresentation.spreadMetric(
            unitCost: 780.00, marketAnchor: 764.55, isInterpolatedMarketAnchor: true, isPendingCloseAnchor: true
        ))
        let pendingFlat = try #require(ChartPurchaseMarkerPresentation.spreadMetric(
            unitCost: 764.55, marketAnchor: 764.55, isInterpolatedMarketAnchor: true, isPendingCloseAnchor: true
        ))
        #expect(pendingPremium.capsuleText == "较最近收盘多花 ¥15.45/g（贵 2.02%）")
        #expect(pendingFlat.capsuleText == "与最近收盘持平 (¥0.00/g)")
        #expect(pendingFlat.compactText == "与最近收盘持平")

        // 5. 零投顾合规词断言
        let allPendingCopy = [
            tooltip.dateBadge ?? "",
            tooltipSpread.capsuleText,
            pendingPremium.capsuleText,
            pendingFlat.capsuleText,
            pendingFlat.compactText,
            statusBadge ?? "",
            refTitle,
            explanation,
            "· 视口外有 2 笔买入"
        ].joined(separator: " ")

        let forbiddenAdvisoryTerms = [
            "建议", "推荐", "抄底", "逢低", "加仓", "减仓", "追高",
            "止盈", "止损", "看涨", "看跌", "买入时机", "投资机会", "必涨", "目标价"
        ]
        for term in forbiddenAdvisoryTerms {
            #expect(!allPendingCopy.contains(term), "待收盘文案不得包含投顾违规词：\(term)")
        }
    }

    @MainActor
    @Test("模拟器实拍 v58：待收盘挂靠红点+虚线金环+纵轴微扩、半屏明细抽屉、视口外买入轻量提示")
    func renderTrailingMarkerVisualReview() async throws {
        let now = Date.now
        let cal = Calendar.current
        let today = ChartViewport.noon(now, calendar: cal)
        let yesterday = ChartViewport.noon(cal.date(byAdding: .day, value: -1, to: now)!, calendar: cal)

        // 构造近 30 天交易日收盘序列，末尾交易日（如周日 11/22 对应周五 11/20）设为最低价 ¥764.55，验证纵轴平滑微扩且右下角最低气泡不遮挡红点
        var dailyPrices: [GoldDailyPrice] = []
        var tradingDays: [Date] = []
        for offset in stride(from: -35, through: 0, by: 1) {
            let day = ChartViewport.noon(cal.date(byAdding: .day, value: offset, to: yesterday)!, calendar: cal)
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }
            tradingDays.append(day)
        }
        let count = max(1, tradingDays.count)
        for (idx, day) in tradingDays.enumerated() {
            let progress = Double(idx) / Double(max(1, count - 1))
            let close: Double
            if idx == count - 1 {
                close = 764.55
            } else {
                let wave = sin(progress * .pi * 2.1) * 16.0 + (1.0 - progress) * 28.0
                close = max(768.0, (774.0 + wave).rounded() + 0.25)
            }
            dailyPrices.append(GoldDailyPrice(date: day, open: close + 1.0, high: close + 2.8, low: close - 1.5, close: close))
        }
        let latestClose = dailyPrices.last?.close ?? 764.55
        let quote = GoldQuote(
            symbol: "AU9999",
            price: latestClose,
            open: latestClose,
            high: latestClose + 3.2,
            low: latestClose - 1.0,
            prevClose: latestClose,
            usdCNY: 0,
            cnyPerGram: latestClose,
            asOf: now
        )

        let mockService = MockMarkerChartService(daily: dailyPrices, quote: quote)
        let chartModel = MarketHomeViewModel(
            basis: .domestic,
            dailyService: mockService,
            quoteService: mockService,
            realtimeService: mockService,
            historyService: mockService
        )
        chartModel.range = .month
        await chartModel.refresh()

        // 场景 1 & 2：当日（周日 11/22）以 ¥755.01 录入第一笔黄金（低于前日最低 ¥764.55 仅 1.25%）
        let recToday = HoldingRecord(grams: 10, unitPriceCNY: 755.01, timestamp: today, note: "新手首笔攒金")
        recToday.assetType = GoldAssetType.accumulation.rawValue
        recToday.brand = "工商银行"
        recToday.laborFee = 0

        let trailingOverlay = try #require(HoldingsInsights.marketOverlay(
            entries: [recToday.insightEntry],
            window: nil,
            referencePrice: quote.cnyPerGram,
            calendar: cal
        ))

        let visibleData = chartModel.visiblePoints
        let expandedDomain = ChartHoldingMarkerResolver.expandedPriceDomain(
            curvePoints: visibleData,
            markers: trailingOverlay.markers,
            xDomain: chartModel.xDomain,
            scale: chartModel.priceScale,
            calendar: cal
        )
        let resolvedTrailing = ChartHoldingMarkerResolver.resolve(
            markers: trailingOverlay.markers,
            curvePoints: visibleData,
            scale: chartModel.priceScale,
            domain: expandedDomain,
            xDomain: chartModel.xDomain,
            calendar: cal
        )
        let pendingMarker = try #require(resolvedTrailing.first)
        #expect(pendingMarker.isPendingCloseAnchor == true)
        #expect(pendingMarker.marker.date == today)

        // 场景 3：2 笔较早的历史买入落在当前近一月视口之外 -> 顶部展示「· 视口外有 2 笔买入」
        let oldDay1 = ChartViewport.noon(cal.date(byAdding: .day, value: -75, to: yesterday)!, calendar: cal)
        let oldDay2 = ChartViewport.noon(cal.date(byAdding: .day, value: -60, to: yesterday)!, calendar: cal)
        let oldRec1 = HoldingRecord(grams: 10, unitPriceCNY: 742.0, timestamp: oldDay1, note: "历史定投1")
        oldRec1.assetType = GoldAssetType.bar.rawValue
        oldRec1.brand = "中国黄金"
        let oldRec2 = HoldingRecord(grams: 5, unitPriceCNY: 750.0, timestamp: oldDay2, note: "历史定投2")
        oldRec2.assetType = GoldAssetType.accumulation.rawValue
        oldRec2.brand = "建设银行"
        let outOverlay = try #require(HoldingsInsights.marketOverlay(
            entries: [oldRec1.insightEntry, oldRec2.insightEntry],
            window: nil,
            referencePrice: quote.cnyPerGram,
            calendar: cal
        ))
        let outResolved = ChartHoldingMarkerResolver.resolve(
            markers: outOverlay.markers,
            curvePoints: visibleData,
            scale: chartModel.priceScale,
            domain: chartModel.priceScale.domain(visibleData.map(\.price)),
            xDomain: chartModel.xDomain,
            calendar: cal
        )
        #expect(outResolved.isEmpty)
        #expect(ChartHoldingMarkerResolver.outOfViewportPurchaseCount(allMarkers: outOverlay.markers, resolvedMarkers: outResolved) == 2)

        let phoneSize = CGSize(width: 393, height: 852)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)

        let panel1 = AnyView(
            VStack(spacing: 0) {
                MarketHomeChartContent(
                    model: chartModel,
                    availableHeight: 740,
                    showingHistorySources: .constant(false),
                    showingDates: .constant(false),
                    holdingOverlay: trailingOverlay,
                    showHoldingOverlay: true,
                    hideAmounts: false,
                    onToggleHoldingOverlay: {},
                    onSelectPurchaseMarker: { _ in }
                )
                .padding(.horizontal, 18)
                .padding(.top, 58)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        let panel2 = AnyView(
            ZStack(alignment: .bottom) {
                panel1
                    .opacity(0.32)
                ChartPurchaseMarkerSheet(
                    resolvedMarker: pendingMarker,
                    marketBasis: .domestic,
                    hideAmounts: false,
                    currentQuote: quote,
                    recordLookup: { $0 == recToday.id ? recToday : nil }
                )
                .frame(height: 540)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous)
                        .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        let panel3 = AnyView(
            VStack(spacing: 0) {
                MarketHomeChartContent(
                    model: chartModel,
                    availableHeight: 740,
                    showingHistorySources: .constant(false),
                    showingDates: .constant(false),
                    holdingOverlay: outOverlay,
                    showHoldingOverlay: true,
                    hideAmounts: false,
                    onToggleHoldingOverlay: {},
                    onSelectPurchaseMarker: { _ in }
                )
                .padding(.horizontal, 18)
                .padding(.top, 58)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        let panels: [(String, AnyView)] = [
            ("1. 待收盘挂靠末端 + 虚线金环 + Y轴微扩", panel1),
            ("2. 轻点挂靠红点 · 待收盘半屏抽屉", panel2),
            ("3. 无红点视口 · 视口外有 2 笔买入", panel3)
        ]

        var captured: [(String, UIImage)] = []
        for (title, rootView) in panels {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: phoneSize)
            let controller = UIHostingController(
                rootView: rootView
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .dark
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(220))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let png = try #require(image.pngData())
            #expect(png.count > 10_000)
            captured.append((title, image))
            window.isHidden = true
            await Task.yield()
        }
        previousKey?.makeKey()

        let composite = Self.composeReviewStrip(captured, tileSize: phoneSize)
        let pngData = try #require(composite.pngData())
        #expect(pngData.count > 30_000)

        let scratchDir = URL(fileURLWithPath: "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch", isDirectory: true)
        if FileManager.default.fileExists(atPath: scratchDir.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
            let outURL = scratchDir.appendingPathComponent("sim_trailing_marker_v58.png")
            try? pngData.write(to: outURL, options: .atomic)
            print("TRAILING_MARKER_ARTIFACT: \(outURL.path)")
        } else {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("sim_trailing_marker_v58.png")
            try? pngData.write(to: fallback, options: .atomic)
            print("TRAILING_MARKER_ARTIFACT: \(fallback.path)")
        }
    }

    @MainActor
    @Test("模拟器实拍：走势图红点图例、单/多笔角标、滑查浮窗与多笔明细半屏抽屉")
    func renderMarkerTipsAndSheetForVisualReview() async throws {
        let now = Date.now
        let cal = Calendar.current
        let endDay = ChartViewport.noon(cal.date(byAdding: .day, value: -1, to: now)!, calendar: cal)

        // 构造近 90 天国内 Au99.99 真实感交易日收盘序列（跳过周末）
        var dailyPrices: [GoldDailyPrice] = []
        var tradingDays: [Date] = []
        for offset in stride(from: -88, through: 0, by: 1) {
            let day = ChartViewport.noon(cal.date(byAdding: .day, value: offset, to: endDay)!, calendar: cal)
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }
            let t = Double(offset + 88) / 88.0
            let wave = sin(t * .pi * 3.2) * 18.0 + cos(t * .pi * 1.4) * 10.0
            let close = (720.0 + t * 52.0 + wave).rounded()
            dailyPrices.append(GoldDailyPrice(date: day, open: close - 1.5, high: close + 2.5, low: close - 3.0, close: close))
            tradingDays.append(day)
        }
        let latestClose = dailyPrices.last?.close ?? 775.0
        let quote = GoldQuote(
            symbol: "AU9999",
            price: latestClose + 3.4,
            open: latestClose - 1.2,
            high: latestClose + 6.1,
            low: latestClose - 3.5,
            prevClose: latestClose,
            usdCNY: 0,
            cnyPerGram: latestClose + 3.4,
            asOf: now
        )

        let mockService = MockMarkerChartService(daily: dailyPrices, quote: quote)
        let chartModel = MarketHomeViewModel(
            basis: .domestic,
            dailyService: mockService,
            quoteService: mockService,
            realtimeService: mockService,
            historyService: mockService
        )
        chartModel.range = .quarter
        await chartModel.refresh()

        let singleIdx = max(0, tradingDays.count / 3)
        let multiIdx = max(0, (tradingDays.count * 2) / 3)
        let singleDay = tradingDays[singleIdx]
        let multiDay = tradingDays[multiIdx]
        let singleDayClose = dailyPrices[singleIdx].close
        let multiDayClose = dailyPrices[multiIdx].close

        // 构造真实 HoldingRecord 以便半屏抽屉展示右箭头与直达 HoldingDetailView 能力
        let recSingle = HoldingRecord(grams: 10, unitPriceCNY: singleDayClose - 6.0, timestamp: singleDay, note: "银行投资金条")
        recSingle.assetType = GoldAssetType.bar.rawValue
        recSingle.brand = "建设银行"
        recSingle.laborFee = 80

        let recMulti1 = HoldingRecord(grams: 15, unitPriceCNY: multiDayClose - 3.0, timestamp: multiDay.addingTimeInterval(-3600), note: "定投积存金")
        recMulti1.assetType = GoldAssetType.accumulation.rawValue
        recMulti1.brand = "工商银行"
        recMulti1.laborFee = 0

        let recMulti2 = HoldingRecord(grams: 10, unitPriceCNY: multiDayClose + 4.0, timestamp: multiDay, note: "10g 工艺金条")
        recMulti2.assetType = GoldAssetType.bar.rawValue
        recMulti2.brand = "中国黄金"
        recMulti2.laborFee = 120

        let recMulti3 = HoldingRecord(grams: 5, unitPriceCNY: multiDayClose + 12.0, timestamp: multiDay.addingTimeInterval(3600), note: "古法黄金手链")
        recMulti3.assetType = GoldAssetType.jewelry.rawValue
        recMulti3.brand = "周大福"
        recMulti3.laborFee = 260

        let records = [recSingle, recMulti1, recMulti2, recMulti3]
        let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        let overlay = try #require(HoldingsInsights.marketOverlay(
            entries: records.map(\.insightEntry),
            window: chartModel.xDomain,
            referencePrice: quote.cnyPerGram,
            calendar: cal
        ))

        let visibleData = chartModel.visiblePoints
        let priceDomain = chartModel.priceScale.domain(visibleData.map(\.price))
        let resolvedMarkers = ChartHoldingMarkerResolver.resolve(
            markers: overlay.markers,
            curvePoints: visibleData,
            scale: chartModel.priceScale,
            domain: priceDomain,
            calendar: cal
        )
        let multiResolved = try #require(resolvedMarkers.first { $0.marker.count == 3 })

        let phoneSize = CGSize(width: 393, height: 852)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)

        // 1. 静默态：展示 `持仓` 开关、`· ● 买入点` 图例、单笔红点 + 3 笔角标红点
        let chartIdleView = AnyView(
            VStack(spacing: 0) {
                MarketHomeChartContent(
                    model: chartModel,
                    availableHeight: 740,
                    showingHistorySources: .constant(false),
                    showingDates: .constant(false),
                    holdingOverlay: overlay,
                    showHoldingOverlay: true,
                    hideAmounts: false,
                    onToggleHoldingOverlay: {},
                    onSelectPurchaseMarker: { _ in }
                )
                .padding(.horizontal, 18)
                .padding(.top, 58)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        // 2. 滑动查价展开多笔买入 Tips 浮窗（选中 3 笔聚合红点当日）
        let inspectModel = chartModel.makeDisplaySnapshot()
        inspectModel.selectedDate = multiDay
        let chartInspectView = AnyView(
            VStack(spacing: 0) {
                MarketHomeChartContent(
                    model: inspectModel,
                    availableHeight: 740,
                    showingHistorySources: .constant(false),
                    showingDates: .constant(false),
                    holdingOverlay: overlay,
                    showHoldingOverlay: true,
                    hideAmounts: false,
                    onToggleHoldingOverlay: {},
                    onSelectPurchaseMarker: { _ in }
                )
                .padding(.horizontal, 18)
                .padding(.top, 58)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        // 3. 轻点 3 笔多笔红点弹出的 ChartPurchaseMarkerSheet 半屏抽屉
        let sheetView = AnyView(
            ZStack(alignment: .bottom) {
                chartIdleView
                    .opacity(0.32)
                ChartPurchaseMarkerSheet(
                    resolvedMarker: multiResolved,
                    marketBasis: .domestic,
                    hideAmounts: false,
                    currentQuote: quote,
                    recordLookup: { recordByID[$0] }
                )
                .frame(height: 588)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24, style: .continuous)
                        .strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoldTheme.background)
        )

        let panels: [(String, AnyView)] = [
            ("1. 静默态 · 图例与多笔角标", chartIdleView),
            ("2. 滑动查价 · 展开买入 Tips", chartInspectView),
            ("3. 轻点多笔红点 · 半屏明细抽屉", sheetView)
        ]

        var captured: [(String, UIImage)] = []
        for (title, rootView) in panels {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: phoneSize)
            let controller = UIHostingController(
                rootView: rootView
                    .preferredColorScheme(.dark)
                    .tint(GoldTheme.gold)
            )
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = .dark
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(220))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let png = try #require(image.pngData())
            #expect(png.count > 10_000)
            captured.append((title, image))
            window.isHidden = true
            await Task.yield()
        }
        previousKey?.makeKey()

        let composite = Self.composeReviewStrip(captured, tileSize: phoneSize)
        let pngData = try #require(composite.pngData())
        #expect(pngData.count > 30_000)

        let scratchDir = URL(fileURLWithPath: "/Users/carlwang/.gemini/antigravity/brain/77e4602c-38ee-4d0a-9163-02d8952f541c/scratch", isDirectory: true)
        if FileManager.default.fileExists(atPath: scratchDir.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
            let outURL = scratchDir.appendingPathComponent("sim_marker_tips.png")
            try? pngData.write(to: outURL, options: .atomic)
            print("MARKER_TIPS_ARTIFACT: \(outURL.path)")
        } else {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("sim_marker_tips.png")
            try? pngData.write(to: fallback, options: .atomic)
            print("MARKER_TIPS_ARTIFACT: \(fallback.path)")
        }
    }

    @MainActor
    private static func composeReviewStrip(_ items: [(String, UIImage)], tileSize: CGSize) -> UIImage {
        let padding: CGFloat = 24
        let headerHeight: CGFloat = 40
        let count = CGFloat(items.count)
        let totalSize = CGSize(
            width: padding * (count + 1) + tileSize.width * count,
            height: padding * 2 + headerHeight + tileSize.height
        )
        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { context in
            UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: totalSize))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(red: 1.0, green: 0.88, blue: 0.54, alpha: 1)
            ]
            for (index, item) in items.enumerated() {
                let x = padding + CGFloat(index) * (tileSize.width + padding)
                let labelRect = CGRect(x: x + 4, y: padding + 6, width: tileSize.width - 8, height: 28)
                item.0.draw(in: labelRect, withAttributes: titleAttributes)

                let frame = CGRect(x: x, y: padding + headerHeight, width: tileSize.width, height: tileSize.height)
                let clipPath = UIBezierPath(roundedRect: frame, cornerRadius: 24)
                context.cgContext.saveGState()
                clipPath.addClip()
                item.1.draw(in: frame)
                context.cgContext.restoreGState()

                UIColor(white: 1, alpha: 0.14).setStroke()
                clipPath.lineWidth = 1.5
                clipPath.stroke()
            }
        }
    }
}

private struct MockMarkerChartService: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing, GoldHistoryServicing, Sendable {
    let daily: [GoldDailyPrice]
    let quote: GoldQuote

    func fetchDailyPrices() async throws -> [GoldDailyPrice] { daily }
    func cachedDailyPrices() async -> [GoldDailyPrice]? { daily }
    func fetchQuote() async throws -> GoldQuote { quote }
    func cachedQuote() async -> GoldQuote? { quote }
    func fetchRealtime() async throws -> [MarketChartPoint] { [] }
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        daily.map { GoldHistoryPoint(date: $0.date, price: $0.close, granularity: .daily, source: "mock") }
    }
    func cachedHistory() async -> [GoldHistoryPoint]? {
        daily.map { GoldHistoryPoint(date: $0.date, price: $0.close, granularity: .daily, source: "mock") }
    }
}
