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
        #expect(spreadPremium.capsuleText.contains("+¥36.10/g"))
        #expect(spreadDiscount.capsuleText.contains("-¥4.20/g"))

        let allCopy = [
            ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: false),
            ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: true),
            spreadPremium.capsuleText,
            spreadDiscount.capsuleText,
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
