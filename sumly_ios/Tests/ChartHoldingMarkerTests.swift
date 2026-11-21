import Foundation
import Testing
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
}
